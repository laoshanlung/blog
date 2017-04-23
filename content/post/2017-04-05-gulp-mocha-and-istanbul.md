+++
date = "2017-04-05T23:18:07+03:00"
title = "Gulp, Mocha and Istanbul"
tags = ['nodejs', 'javascript', 'gulp', 'mocha', 'istanbul']
categories = ['Programming']
+++

Yes... you read that right, I am still using `gulp`. Recently, with all the hype and the fact that most of the people I know are switching to npm scripts, `gulp` seems to be something in the distant past. But, here I am, still using `gulp` because with `gulp` or similar task manager libraries, you can share the tasks between your projects. Or you can even have a set of tasks that you usually use in your side projects in one git repository and re-use them every time you have some brilliant ideas and want to roll a new side project (and quickly abandon it like I often do).

<!--more-->

In my thesis, I am writting a framework consisting of around 10 sub-projects, copy and paste npm scripts is a job that I definitely don't want to do. Imaging that you have to change something in one of the npm scripts in one of the projects and you have to go though all 10 projects to update the change. Of course, there are ways to automate that, good old bash scripts or maybe even a JS file to do it. But the point is that I prefer having common stuff in one place and when I modify something, the rest will instantly get the new stuff.

## Mocha
Mocha is a [fun, simple, flexible JavaScript test framework](https://mochajs.org/). It has been around for a very long time. My goal is to have a simple gulp `test` task using `mocha`, so that I can run `gulp test` to test my projects. Since the projects' structure are identical, having a common `test` task is straightforward.

```javascript
gulp.task('test', function() {
  const cwd = process.cwd();

  loadSpecs();

  // set all the tools needed for testing globally
  global.expect = require('chai').expect;
  global.sinon = require('sinon');

  mocha.run(function(failures) {
    process.on('exit', function () {
      process.exit(failures);
    });
  });
});
```

All the black magic happens in `loadSpecs` which simply goes through all the folders inside `src` folder recursively to load spec files (having `.spec` in the file name)

```javascript
function getAllFilesFromPath(path) {
  const stat = fs.statSync(path);
  if (stat.isDirectory()) {
    return _.chain(fs.readdirSync(path)).map(function(file) {
      return getAllFilesFromPath(path + '/' + file);
    }).flatten().value();
  } else if (stat.isFile()) {
    return [path];
  }
  return null;
}

function loadSpecs() {
  const cwd = process.cwd();
  // I put all the modules in src folder in each project
  getAllFilesFromPath(`${cwd}/src`).forEach(function(path) {
    if (path.indexOf('.spec') != -1) {
      mocha.addFile(path);
    }
  });
}
```

Since this is only for testing, I don't need to optimize anything, just use `statSync` and `readdirSync`. And that is the simplest from of `mocha` setup for `gulp`. More info about [how to use mocha programmatically](https://github.com/mochajs/mocha/wiki/Using-mocha-programmatically)

## Istanbul
[Istanbul](https://istanbul.js.org/) is a test coverage library to let people know how well their tests cover the source code. Using istanbul from command line is the easiest thing I have seen so far, just run it with `mocha` like this `nyc mocha` and you are good to go. However, using it programmatically requires a bit more work. In fact, I needed to dig around for a solid 57 minutes to figure out how to make it work with `mocha`. The secret sauce is this [hook](https://github.com/istanbuljs/istanbuljs/blob/master/packages/istanbul-lib-hook/lib/hook.js) which can be access through `istanbul.hook`. Let me show the code first and then explain it

```javascript
const istanbul = require('istanbul')

function hookRequire() {
  const instrumenter = new istanbul.Instrumenter();
  const cwd = process.cwd();
  const fileMap = {};
  istanbul.hook.unhookRequire();
  istanbul.hook.hookRequire(function (path) {
    const parts = path.split(cwd).filter(Boolean);

    return !fileMap[path]
      // ignore node_module
      && path.indexOf('node_module') === -1
      // ignore spec files
      && path.indexOf('.spec') === -1
      // ignore anything outside the current working directory
      && parts.length === 1
      && parts[0].indexOf('/src') === 0;
  }, function (code, path) {
    fileMap[path] = instrumenter.instrumentSync(code, path);
    return fileMap[path];
  });
}
```

Note that `hookRequire` needs to be called before you actually require anything. In this example, it should be called before `loadSpecs`. The idea is to hook into `require` and alter the required module to let istanbul instrument the code. However you don't want to instrument everything, for example, stuff from `node_module` or your spec files.

`istanbul.hook.hookRequire` accepts 2 params which are 2 functions and another optional `options` object. The first one is the `matcher` which checks whether a module needs to be transformed (instrumented) or not. The second one is the transformer which is where I use `istanbul.instrumenter` to instrument the code. Then, when my tests run through the already instrumented code, `istanbul` records the coverage (default to `global.__coverage__`). The coverage data later can be used to generate a report.

Another thing worth noticing is that the whole thing is synchronous because of the way nodejs requires modules. It always happens synchronously and there is nothing we can do about it. It might be slower (compared to the asynchronous counterpart) but it does the job.

The final piece is to generate a coverage report. In my case I only need 2 reports, `text` and `html`. `text` report is the one you will see when your tests end. `html` report contains a lot more information such as the coverage percentage of each file.

```javascript
function summarizeCoverage() {
  const cwd = process.cwd();
  const coverage = global.__coverage__;
  if (!coverage) {
    console.warn('Unable to find coverage data');
    return;
  }

  const collector = new istanbul.Collector();
  collector.add(coverage);

  const reporter = new istanbul.Reporter(null, `${cwd}/coverage`);
  reporter.addAll([ 'text', 'html' ]);
  reporter.write(collector, true, () => {});
};
```

With all that said and done, I have a re-usable `test` task that I can use in my side projects. I might need to modify it a bit to adapt to my future project structure, but for now it's good enough for my needs.

## What wrong with npm scripts?
I have nothing against npm scripts, in fact I have been using them regularly for the past 2 years. It's just that I need something that can be shared between my projects.
