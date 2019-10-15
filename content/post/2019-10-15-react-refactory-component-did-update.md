+++
date = "2019-10-15T12:24:29+02:00"
title = "Migrate from componentDidUpdate to React hooks"
tags = ['javascript', 'react']
categories = ['Programming']
+++

We have recently updated to React 16.8 after more than 1 year stuck with the old version. The process was surprisingly pleasant, in fact, I accidentally updated our React version to 16.8 and we didn't notice it for 1 week, nothing broken as we have gradually got rid of all the legacy stuff. Now that we have updated to 16.8, the fun officially begins. I have been a regular guest in the refactory hotel recently and I decided to write down some interesting cases I have encountered during my journey.

<!--more-->
<div class="img">
  <img src="/gifs/mind-blown-tenor.gif" />
</div>

Before I write anything, I have to admit that despite all the good things React hooks bring to the table, I still think that it has too much magic behind the scene. For example, `useState` looks very simple but the fiber architecture to support it is much more complicated. It reminds me a lot about the time when I approached Ruby on Rails. Its magic can be good or bad depending on the situation.

Anyway, one of the common patterns we have in our code base is to use `componentDidUpdate` to reset some state after an API call finishes. For example, in an input field, we want to change it from "editting" state to "static" state after its value has been saved.

<p class="codepen" data-height="265" data-theme-id="0" data-default-tab="js,result" data-user="tanqhnguyen" data-slug-hash="VwwjwRR" style="height: 265px; box-sizing: border-box; display: flex; align-items: center; justify-content: center; border: 2px solid; margin: 1em 0; padding: 1em;" data-pen-title="VwwjwRR">
  <span>See the Pen <a href="https://codepen.io/tanqhnguyen/pen/VwwjwRR">
  VwwjwRR</a> by Tan Nguyen (<a href="https://codepen.io/tanqhnguyen">@tanqhnguyen</a>)
  on <a href="https://codepen.io">CodePen</a>.</span>
</p>

In this example, I use `simulateFluxFlow` to simulate our Redux flow where we have the typical action and reducer to handle the API call and pass the result or any loading indicator as props to the "container" component.

`NameInput` is a pure graphical component which knows nothing about the logic to handle its state. `NameInputLogic` as the name implies encapsulate all the state management of `NameInput`. In reality, depending on how complicated the logic is, we put them into a higher order component (like `NameInputLogic`) or in the reducer. My goal is to refactor `NameInputLogic` to use React hooks. The first thing to be refactored is the state, with `useState`, we can get rid of `React.Component` and instead go for the functional one.

```js
function NameInputLogic(props) {
  const [isEditting, setIsEditting] = useState(false);
  const [value, setValue] = useState('');

  return <NameInput
    value={value}
    isEditting={isEditting}
    isLoading={props.isLoading}
    onChange={(value) => {
      setValue(value);
    }}
    onEdit={() => {
      setIsEditting(true);
    }}
    onSave={() => {
      props.submitValue(value);
    }}
  />;
}
```

A lot simpler than before, but... it doesn't exactly do what we want it to do because the input is still in "editting" mode after we save it.

<p class="codepen" data-height="265" data-theme-id="0" data-default-tab="js,result" data-user="tanqhnguyen" data-slug-hash="MWWeYXB" style="height: 265px; box-sizing: border-box; display: flex; align-items: center; justify-content: center; border: 2px solid; margin: 1em 0; padding: 1em;" data-pen-title="Refactored to use useState">
  <span>See the Pen <a href="https://codepen.io/tanqhnguyen/pen/MWWeYXB">
  Refactored to use useState</a> by Tan Nguyen (<a href="https://codepen.io/tanqhnguyen">@tanqhnguyen</a>)
  on <a href="https://codepen.io">CodePen</a>.</span>
</p>

Fortunately, there is this FAQ [How to get the previous props or state?](https://reactjs.org/docs/hooks-faq.html#how-to-get-the-previous-props-or-state)

<div class="img">
  <img src="/images/real-mvp.jpg" />
</div>

```js
function usePrevious(value) {
  const ref = useRef();
  useEffect(() => {
    ref.current = value;
  });
  return ref.current;
}
```

`useRef` is a black box used to store any kind of value in its `current` property. And the same ref is returned every time React re-renders the component. When used together with `useEffect`, we can record the current value and return the previously stored value.

That solves the first part where we need to get the previous value to compare with the current value. Now we need to have a way to trigger the logic. It's where `useEffect` shines. `useEffect` is used to perform side effects, and this is the exact thing we are doing now, side effect!

```js
function NameInputLogic(props) {
  const [isEditting, setIsEditting] = useState(false);
  const [value, setValue] = useState('');

  const {
    isLoading
  } = props

  const prevIsLoading = usePrevious(isLoading);
  useEffect(() => {
    if (prevIsLoading && !isLoading) {
      setIsEditting(false);
    }
  }, [isLoading]);

  //... the rest of the code
}
```

The 2nd parameter passed to `useEffect` tells it to listen to changes happened to the provided "values". I don't know yet how they detect that but let's just trust that React knows. And that's everything we need to do in order to replace `componentDidUpdate` with React hooks. I am pretty sure there are better ways to do it but right now this solution is good enough.

<p class="codepen" data-height="265" data-theme-id="0" data-default-tab="js,result" data-user="tanqhnguyen" data-slug-hash="poobvGZ" style="height: 265px; box-sizing: border-box; display: flex; align-items: center; justify-content: center; border: 2px solid; margin: 1em 0; padding: 1em;" data-pen-title="Refactor componentDidUpdate">
  <span>See the Pen <a href="https://codepen.io/tanqhnguyen/pen/poobvGZ">
  Refactor componentDidUpdate</a> by Tan Nguyen (<a href="https://codepen.io/tanqhnguyen">@tanqhnguyen</a>)
  on <a href="https://codepen.io">CodePen</a>.</span>
</p>