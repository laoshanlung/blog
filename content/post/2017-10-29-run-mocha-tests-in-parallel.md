+++
date = "2017-10-29T11:52:29+02:00"
title = "Running mocha tests in parallel"
tags = ['mocha', 'javascript', 'nodejs']
categories = ['Programming']
+++

In a project, there usually are a lot of tests. I am not going to discuss how much testing is enough because it depends on each project. What I am going to do in this blog post is to write down what I did for my work project to split a huge mocha test suite into smaller suites and run them in parallel. The end result is a testing process that used to take 7 minutes, now takes around 3 minutes. And the more test suites I run in parallel the faster it becomes.

<!--more-->

# Basic setup
The test that I am going to split is a big test that covers most of the system from database queries to api responses. This test requires an actual database connection to work.

There is one `specs.js` file to perform basic operations to set up the database such as running migrations and then load all the test suites

```js
// specs.js
describe('test', function() {
  before(function() {
    return db.migrateUp();
  });

  recursivelyLoadTest(__dirname + '/suites');

  after(function() {
    return db.migrateDown();
  });
});
```

The structure of `suites` folder looks like this
```
suites/
├── user/
│   ├── register.js
│   ├── login.js
│   ├── createProduct.js
│   └── createComment.js
└── product/
    ├── create.js
    └── addComment.js
```

Each js file is a test suite, together they test a specific service (`user` or `product`). And they use normal Mocha BDD-style functions (`describer`, `it`) to test stuff.

As for `recursivelyLoadTest`, it's just a simple function that recursively goes through `suites` and its sub folders to find tests. When it has found a test, it just does `require` to include the test in `specs.js`. There is nothing fancy about it.

# The problem
It starts with a very simple setup and as the project grows, we start adding more and more tests, and it takes longer and longer to run tests. One day when it has reached 7 minutes, I couldn't take it anymore and decided to do something about that. At first, I thought that I could just create new processes using [child_process module](https://nodejs.org/api/child_process.html) and split it so that each test suite will be run in a separate process. It actually works if there are no databases involved. Unfortunately it does in my case. If I have tests running in parallel, and they all make changes to the database, everything will be in an inconsistent state all the time.

My first thought was to just set up multiple database servers and assign each of them to each testing process created by using [child_process module](https://nodejs.org/api/child_process.html). It works perfectly but the setup phase takes too long even with docker containers. And it doesn't work with our current integration service (Codeship) because they only offer one database server (for each version) for each build.

Ok, so no new servers, the only option left is to have multiple databases on the same server, each process needs 1 database, so the total amount of databases that I need is the same as the number of processes. This also works for Codeship because they are nice enough to provide us 10 test databases, so we could theoritically run 10 processes for testing.

# The new setup
In order to support this, I need to have one main entry point, and from that multiple child processes will be created to run the actual test. I will call the main file `test.js` and each child processes is executed via `child.js`.

## The main process (`test.js`)
This file is the entry point for the whole testing process.

```js
// test.js
const Promise = require('bluebird');
const { fork } = require('child_process');

const processes = [
  'user',
  'product'
];

const result = {
  pass: 0,
  fail: 0,
  pending: 0
};

return Promise.mapSeries(processes, (testSuite, index) => {
  const db = `test_database_${index}`;

  return dropDatabaseIfExists(db).then(() => {
    return createDatabase(db).then(() => {
      return runMigrationFor(db);
    });
  }).then(() => {
    return {
      testSuite,
      db
    };
  });
}).map(({testSuite, db}) => {
  return new Promise((resolve) => {
    const proc = fork(path.join(__dirname, 'child.js'), process.argv.slice(2), {
      env: Object.assign({}, process.env, {
        TEST_SUITE: testSuite,
        TEST_DB: db
      })
    });

    proc.on('message', ({message}) => {
      switch (message) {
        case 'end':
          resolve();
          break;
        case 'pass':
        case 'fail':
        case 'pending':
          result[message]++;
          break;
        default: break;
      }
    });

    // terminate children.
    process.on('SIGTERM', function () {
      proc.kill('SIGINT'); // calls runner.abort()
      proc.kill('SIGTERM'); // if that didn't work, we're probably in an infinite loop, so make it die.
      dropDatabaseIfExists(db);
    });

    process.on('SIGINT', function () {
      proc.kill('SIGINT'); // calls runner.abort()
      proc.kill('SIGTERM'); // if that didn't work, we're probably in an infinite loop, so make it die.
      dropDatabaseIfExists(db);
    });
  });
}).catch((error) => {
  console.error(error);
  result.fail += 1;
}).finally(() => {
  console.log('\x1b[32m', `${result.pass} passing`);
  console.log('\x1b[31m', `${result.fail} failing`);
  console.log('\x1b[33m', `${result.pending} pending`);

  return dropAllTestDatabases().then(() => {
    process.exit(result.fail);
  });
});
```

The first thing that I need to do is to set up the test database and run migrations for it. However, during each test run, there might be some problems causing the test database to persist after the test finishes. To deal with that, I simply drop the test database before creating a new one. Each database has their own tables and everything. However, this process can't be run simultaneously because in my case, the migration process also creates new roles which is per server. And if there are multiple calls to create the same role, they will fail.

```js
return dropDatabaseIfExists(db).then(() => {
  return createDatabase(db).then(() => {
    return runMigrationFor(db);
  });
});
```

After setting up the test database, I need to `fork` a new process to run the actual testing logic using the new database that I have just created and set up. I am using `fork` instead of `spawn` because the child processes need to tell their parent process when they have finished running the test. Additionally, they also need to publish events each time they finish a test to let the parent process know and keep track of the results.

```js
const proc = fork(path.join(__dirname, 'child.js'), process.argv.slice(2), {
  env: Object.assign({}, process.env, {
    TEST_SUITE: testSuite,
    TEST_DB: db
  })
});
```

The rest of `test.js` has nothing special, it records how many tests passing/failing/pending and reports the final result. Then, all test databases are dropped to make sure that I don't create a lot of databases for no reasons.

And last but not least, when the test is interrupted, I also need to clean up all the child processes to avoid having zombie processes

```js
// terminate children.
process.on('SIGTERM', function () {
  proc.kill('SIGINT'); // calls runner.abort()
  proc.kill('SIGTERM'); // if that didn't work, we're probably in an infinite loop, so make it die.
  dropDatabaseIfExists(db);
});

process.on('SIGINT', function () {
  proc.kill('SIGINT'); // calls runner.abort()
  proc.kill('SIGTERM'); // if that didn't work, we're probably in an infinite loop, so make it die.
  dropDatabaseIfExists(db);
});
```

## The child process (`child.js`)
There are many ways to do this, one can use the executable `_mocha` file to execute tests, but in my case, I want to experiment something new, so I am going to run mocha programmatically.

```js
// child.js
const Mocha = require('mocha'),
      path = require('path'),
      argv = require('yargs').argv

require('./setup');

const mocha = new Mocha({
  timeout: 60000,
  reporter: 'list',
  bail: true,
  retries: 3,
  grep: argv.grep
});

mocha.addFile(path.join(__dirname, 'runTest'));

const runner = mocha.run((failures) => {
  process.send({message: 'end', failures});
  process.exit(0); // parent will decide exitCode
});

runner.on('pass', () => {
  process.send({message: 'pass'});
});

runner.on('fail', () => {
  process.send({message: 'fail'});
});

runner.on('pending', () => {
  process.send({message: 'pending'});
});
```

This is pretty standard, initializing Mocha, and then add one single test file `runTest`. This is the original file that I use to run all test suites at once (the old setup), it contains all the code to set up testing environment. To make it work with the new setup, I just need to change it so that it doesn't load everything but instead load the specific test suite set via `TEST_SUITE` environment variable.

```js
// runTest.js
const helper = require('./helper');

const suites = (process.env.TEST_SUITE || '').split(',');

describe('integration-test', () => {
  suites.forEach((suite) => {
    describe(suite, () => {
      helper.runTestSuite(`${__dirname}/suites/${suite}`);
    });
  });

  beforeEach(() => {
    return setupStuff();
  });

  afterEach(() => {
    return teardownStuff();
  });
});
```

And with that I have a simple setup for running mocha tests in parallel. In theory, it should work with other testing libraries. It also depends on how you set up your tests. It has been working perfectly so far. However, I might have to do some improvement to make it work with `debug` flag of Node so that I can debug my tests in case something goes wrong.
