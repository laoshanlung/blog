+++
date = "2019-09-30T11:52:29+02:00"
title = "A gentle introduction to Flow(type)"
tags = ['javascript']
categories = ['Programming']
+++

Last week, I was lucky to be able to give a talk at [HelsinkiJS](https://meetabit.com/events/helsinkijs-september-2019). The presentation was rather long compared to other because it introduces the type system as well as Flow. In this blog post I'm gonna summarize my presentation. 

<!--more-->

But first thing first, here is the slide. I will skip all the basic stuff and jump straight to what I think is interesting or what I have learned while preparing the slides.

<iframe src="https://docs.google.com/presentation/d/e/2PACX-1vRW06NeReX0C76SrjxePFVXQP5P9ndq9n_tRl_bACMWMhPpTsEr_q2ej7S0u5aHmA2pUUk9NdZRY_ao/embed?start=false&loop=false&delayms=3000" frameborder="0" width="100%" height="569" allowfullscreen="true" mozallowfullscreen="true" webkitallowfullscreen="true"></iframe>

## What is a type?

Let's actually start with what is a type rather than "why we need a static type checker in JS". A type consists of 2 parts, the name and the structure. For example, if we define a type called `Person`, its structure can have `age` which is a `number` and `name` which is a `string`. So the type checker uses either the name or the structure to distinguish between types.

Comparing types using their name is called **nominal typing**, and using their structure is called **structural typing**. Flow employs both approaches. It uses _nominal typing for comparing classes_ (treated as both value and type) and _structural typing for comparing objects or functions_

For example

```js
type Human = {
  name: string,
  age: number
};

type Dwarf = {
  name: string,
  age: number
}

const person: Human = {
  name: 'Tan',
  age: 90
};

const dwarf: Dwarf = person;
```

## any vs mixed
At first glance, `any` and `mixed` can be very confusing, but they have a subtle difference that can catch you off guard 

<img src="/gifs/same-same-but-different.gif" width="100%" />

- `mixed` is the supertype of all types
- `any` is the supertype **and subtype** of all types

To illustrate this difference I have this piece of code

```js
const mixedString: mixed = 'string';
const anyString: any = 'string';

let realString: string;

realString = anyString;
// yield error
// Cannot assign `mixedString` to `realString` because mixed is incompatible with string
realString = mixedString;
```

## Interfaces are implicit
And last but not least, interfaces in flow can be used implicitly. Although in my opinion this might create some confusion in the code base.

```js
interface Runnable {
  run(): void
}

interface Barkable {
  bark(): void 
}

class Dog {
  run() {}
  bark() {}
}

const golden: Runnable = new Dog();
const lab: Barkable = new Dog();
const shiba: Runnable & Barkable = new Dog();
```

## Final words...
Even though I have been working with flow for more than 2 years, there are still a lot of things to learn about flow. Unfortunately, the more I work with flow, the more I hate its error reporting system. It makes absolutely no sense 80% of the time. I even have regular flow rant on our company's slack channel

<img src="/images/flow-rants.png" />

That's not even all of it... I wish flow had a better error trace to point me to the correct line where the error happens.
