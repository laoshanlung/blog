+++
date = "2018-08-14T11:52:29+02:00"
title = "Dependency injection, why does it matter?"
tags = ['javascript']
categories = ['Programming']
draft = true
+++

Dependency injection is one of the basic programming principles that I learned and still remember. It's a very useful principle but I don't see it being used widely in the Javascript world. From all the Javascript libraries and frameworks that I have used before, only Angular 1 and Loopback force the use of dependency injection. In this blog post, I am going to discuss dependency injection and why is it important for medium to large projects.

<!--more-->

## What?
Dependency injection is mentioned as part of the famous SOLI**D** principle. I don't remember the exact definition but the basic idea is to explicitly define and provide the dependencies of a module. Considering this piece of code

```js
const dep1 = require('./dep1');
const dep2 = require('./dep2');

module.exports = function doSomething() {
  dep1.doThis();
  dep2.doThat();
};
```

This is called implicit dependency where all the dependencies are statically defined and provided, they can't be changed under any circumstances. There are some problems with this approach

1. It's harder to test. If `dep1` is a module that connects to a 3rd party service, we probably don't want to call that service every time we run test. It's not nice.

2. It's not flexible. Once the dependency is defined, it's set in stone, we can't change it anymore. Imagine that we need to use the same module somewhere else, either copy/paste or bundle it as a npm package, the same dependencies need to be installed there.

3. It's difficult to know what a module needs and what to expect when we use it. For example, if a module requires a database connection implicitly, the only way that we can know whether using that module changes anything in the database or not is to read its source code. With dependency injection, when we initialize a module, we must explicitly provide the dependencies which act as a reminder about what the module does.

## Explicit dependencies
The above module can be rewritten so that all the dependencies are explicit, and the caller must provide (inject) them when they want to use the module.

```js
module.exports = function(dep1, dep2) {
  return function doSomething() {
    dep1.doThis();
    dep2.doThat();
  };
};
```

Then the caller needs to do this

```js
const dep1 = require('./dep1');
const dep2 = require('./dep2');
const buildDoSomething = require('./doSomething');

const doSomething = buildDoSomething(dep1, dep2);
doSomething();
```

It's certainly longer and involving more stuff but there are several benefits.

### Easier to test
When we want to test `doSomething`, and we usually don't want to invoke `dep1`, so we can provide a stub for it

```js
const dep1 = require('./dep1Stub');
const dep2 = require('./dep2');
const buildDoSomething = require('./doSomething');

const doSomething = buildDoSomething(dep1, dep2);
describe('doSomething', function() {
  it('should do something', function() {
    expect(doSomething()).to.equal('?');
  });
});
```

There are some other alternatives such as [sinonjs](https://sinonjs.org/) when it comes to mock/stub a module while testing. One can go with implicit dependencies, and use sinon to stub all the methods in `dep1` to test `doSomething`. It totally is a valid approach for testing, in fact I have been using it in a lot of my projects. But as the project grows the same logic to stub a dependency repeats itself and eventually we will end up with the exact same approach where we define a whole new stub module for the dependency. For example, without dependency injection, we can do this with sinon

```js
const sinon = require('sinon')
const dep1 = require('./dep1');
const doSomething = require('./doSomething');

describe('doSomething', function() {
  beforeEach(function() {
    sinon.stub(dep1, 'doThis');
  });

  afterEach(function() {
    dep1.doThis.restore();
  });

  it('should do something', function() {
    expect(doSomething()).to.equal('?');
  });
});
```

As we add more tests the `beforeEach` and `setupEach` need to be repeated. And we will eventually end up with this

```js
const {
  stub,
  restore
} = require('./stubDep1');
const doSomething = require('./doSomething');

describe('doSomething', function() {
  beforeEach(function() {
    stub();
  });

  afterEach(function() {
    restore();
  });

  it('should do something', function() {
    expect(doSomething()).to.equal('?');
  });
});

// stubDep1.js
const sinon = require('sinon');
const dep1 = require('./dep1');

module.exports = {
  stub() {
    sinon.stub(dep1, 'doThis');
  }

  restore() {
    dep1.doThis.restore();
  }
};
```

And if we forget to stub a method of the dependency when we implement a new feature, something bad might happen. For instance, while developing a module, we need to introduce a new call to the 3rd party API through a new method in the dependency. If we forgot to stub the dependency in our tests, everything will still work but we are consuming the API needlessly, in some cases we might even run into a quota limit. On the other hand, if we use dependency injection, and our mocked dependency doesn't have the new method (there is a way to detect this even before running the code, I will cover it shortly), tests will fail.

### More flexible
Injecting the dependencies also brings another benefit when re-using the module. Imagine that we want to implement a cache engine

```js
module.exports = function(storage) {
  return {
    set(key, value, ttl = 1000) {
      return storage.set(key, value, ttl);
    },
    get(key) {
      return storage.get(key);
    },
    del(key) {
      return storage.del(key);
    }
  }
}
```

When we first start the project, there is no need to have any fancy caching mechanism, using memory is more than sufficient. Our memory cache only needs to have 3 methods: `set`, `get` and `del`

```js
// this is a very naive implementation of a memory cache...
module.exports = function memoryCache() {
  let cache = [];
  return {
    set(key, value, ttl) {
      const expired = new Date().getTime() + ttl;
      const existing = cache.find((entry) => {
        return entry.key === key;
      });

      if (!existing) {
        cache.push({
          key,
          value,
          expired
        });
      } else {
        existing.expired = expired;
      }
      return this;
    },
    get(key) {
      const entry = cache.find((entry) => {
        return entry.key === key;
      });
      if (!entry) return null;
      if (entry.expired < new Date().getTime()) {
        this.del(key);
        return null;
      }
      return entry.value;
    },
    del(key) {
      cache = cache.filter((entry) => {
        return entry.key !== key;
      });
      return this;
    }
  }
}
```

As the project grows, we need to scale to multiple processes. At this point, having cached data in the memory is not feasible anymore. Therefore, we need to switch to a different storage (I usually go with Redis). All we need to do now is to implement a different storage based on Redis and replace the memory cache that we have.

### Meet flow
Dependency injection in Javascript shines the brightest when using together with a static type checking system. [Flow](https://flow.org/) happens to be one.

All we need is to define an interface for our dependencies, for example, the cache storage interface can be

```js
interface CacheStorage {
  set(key: string, value: any, ttl?: number): Promise<any>,
  get(key: string): Promise<any>,
  del(key: string): Promise<any>
}

// and the cache
module.exports = function(storage: CacheStorage) {
  return {
    ...
  }
}
```

Having `any` is a bad practice but for the sake of simplicity, I am not going to define all the types.

Using flow also solves the problem mentioned in the testing section when we introduce new methods. When an implementation doesn't meet its interface, flow will complain.

## Final thoughts
Just like with pretty much everything else, dependency injection is no silver bullet. Using it correctly will lead to a clean and flexible architecture while doing it wrong will lead to an unnecessarily complicated architecture. I usually start with something simple to quickly deliver, then while I have a better picture of what I want to build, I will start putting stuff to where they should be.

Dependency injection alone doesn't make much of a difference in the Javascript world due to the lack of types. However, when used with a static type checking like Flow, it really shines. I personally don't like Flow that much, their error reporting is always a mystery, but it does the job.
