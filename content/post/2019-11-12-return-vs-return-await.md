+++
date = "2019-11-12T12:24:29+02:00"
title = "Difference between return and return await"
tags = ['javascript']
categories = ['Programming']
+++

I stumbled upon a weird bug few days ago when I needed to implement a function that will gracefully fail instead of throwing an error. I thought it was as simple as `try` the function and `catch` the error, then return something else. Apparently, with `async`, things got a bit confusing.

<!--more-->

Let's start with the first version

```js
async function doSomething() {
  throw Error('Wooo!');
}

async function mainFunction() {
  try {
    return doSomething();
  } catch (e) {
    console.error(e);
    return false;
  }
}

(async function() {
  const result = await mainFunction();
  console.log('result', result);
})();
```

<div class="img">
  <img src="/images/obi-wan-visible-confusion.jpg" />
</div>

I was surprised that neither the result nor the error was logged. And of course the function didn't work as expected. The only clue I had was

```
(node:14510) UnhandledPromiseRejectionWarning: Error: Wooo!
```

Apparently, my function was treated as an unhandled promise rejection. Let's rewrite it in the good old Promise way

```js
function mainFunction() {
  return doSomething().catch((e) => {
    console.error(e);
    return false;
  });
}
```

It works! So what was wrong? I double checked the documentation of [await](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Operators/await). This paragraph catches my attention

```
The await expression causes async function execution to pause until a Promise is settled, that is fulfilled or rejected, and to resume execution of the async function after fulfillment. When resumed, the value of the await expression is that of the fulfilled Promise.
```

Alright!!! So it was the missing `await` that makes node ignore the `catch` block.

```js
async function mainFunction() {
  try {
    return await doSomething();
  } catch (e) {
    console.error(e);
    return false;
  }
}
```

And now it works with async. However, after trying things out a bit more, I finally understand that we only need to `return await` instead of `return` when used inside a `try...catch` block. In normal cases, we just need to `return`. For example, if I want my `mainFunction` to just throw an error and whoever calls it needs to handle the error accordingly, I can just do

```js
async function mainFunction() {
  return doSomething();
}

(async function() {
  try {
    return await mainFunction();
  } catch (e) {
    console.error('An error');
  }
})();
```

There are no differences in this case between `return` and `return await` because we don't need to pause the execution to wait for `doSomething` to finish but we just return whatever `doSomething` returns which is a Promise. And whoever calls `mainFunction` needs to handle the error if any.

<div class="img">
  <img src="/images/success-kid.jpg" />
</div>


