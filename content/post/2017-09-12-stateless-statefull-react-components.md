+++
date = "2017-09-12T20:45:40+03:00"
title = "Stateless and/or stateful React components"
tags = ['javascript', 'reactjs']
categories = ['Programming']
+++

Although I have been working with React for few years now, the decision between stateless and stateful components is still quite hard for me to make. Stateless components provide a much better and easier to understand flow, while stateful components allow me to develop my application much faster. In this post, I am going to discuss the pros and cons of them and provide my way of writing components that (might) have the best of both worlds (that comes with some drawbacks as well)

<!--more-->

# Stateless
My understanding is that stateless components are those that don't maintain their own state but instead, rely on `props` passed to them from whatever component that wants to use them.

For example, in my application I want to have several tabs, each tab contains a different section. On top of that, there is a "list" of tabs where I can navigate through my sections with ease (typical tabs UI).

The final result is something like this

```html
class App extends Component {
  constructor(props) {
    super(props);

    this.state = {
      active: 'Tab 1'
    };
  }

  onSwitchTab(title) {
    this.setState({
      active: title
    });
  }

  render() {
    return (
      <div className="App container">
        <Tabs active={this.state.active}
          onSwitchTab={this.onSwitchTab.bind(this)}>
          <Tab title="Tab 1">Tab 1 content</Tab>
          <Tab title="Tab 2">Tab 2 content</Tab>
          <Tab title="Tab 3">Tab 3 content</Tab>
        </Tabs>
      </div>
    );
  }
}
```

It's a very simple and straightforward one-way data flow, `Tabs` accepts two props:

- `active` to specify the currently active tab (based on its `title`)
- `onSwitchTab` is a function to notify about tab changes (it passes new tab's title)

If you are curious, here is the implementation of [Tabs](https://github.com/tanqhnguyen/sample-tabs/blob/master/src/lib/Stateless.js) and [Tab](https://github.com/tanqhnguyen/sample-tabs/blob/master/src/lib/Tab.js)

So... in order to use this `Tabs` component I have to manually listen to `onSwitchTab` events and act accordingly (change active tab). It's quite annoying if I have to use it in many places. And that is a problem with stateless components, at some point, they produce a lot of duplicated (boilerplate) code.

I chose this particular case to demonstrate the limitation of stateless components but it doesn't mean that they are bad. In fact, I myself use a lot of stateless components in my personal projects and at work. They are awesome but sometimes I just don't want to use them.

# Stateful
I first came to know the term "stateful" when I was still studying Java programming. To me, stateful React components are those that maintain its internal `state`, in other word, they are the exact opposite of "stateless" components.

Ok, so how does it look? I am going to take `Tabs` component and turn it into stateful, and the final result is

```html
class App extends Component {
  render() {
    return (
      <div className="App container">
        <Tabs>
          <Tab title="Tab 1">Tab 1 content</Tab>
          <Tab title="Tab 2">Tab 2 content</Tab>
          <Tab title="Tab 3">Tab 3 content</Tab>
        </Tabs>
      </div>
    );
  }
}
```

If you are curious, here is the implementation of [Tabs](https://github.com/tanqhnguyen/sample-tabs/blob/master/src/lib/Stateful.js) and [Tab](https://github.com/tanqhnguyen/sample-tabs/blob/master/src/lib/Tab.js)

I basically move the whole logic of handling tab changes from `App` to inside of `Tabs` making it a self-contained component and everything is managed by `Tabs`. The advantage is to have less code involved to change a tab. It's a big gain in cases where you have one tiny component and you don't care about its operation and/or events (for example, tooltips, hints, notifications etc...)

So, what is the problem with stateful components? They can't be changed from the outside. Since the component manages its internal state by itself, there is no way to interact with it. For example, what if I want to specify the default active tab? One way is to implicitly specify the initially active tab through the order of which I put the `Tab` components (first `Tab` is active by default). But it's not really a good way to specify thing.

And what if I want to have another `select` tag to change the active tab, I can't do it because there is no way to tell `Tabs` which `Tab` is the active one.

How about a mix of stateful and stateless? A component that operates as a stateless component by default and when needed can act as a stateful one. I am not sure what to call it (maybe someone has already named it), but the word that first comes to my mind is "hybrid".

# Hybrid
My own definition is that hybrid components are those that can operate as both stateless and stateful (surprised!). Anyway, let's rewrite `Tabs` to make it "hybrid". From the implementation of [stateless Tabs](https://github.com/tanqhnguyen/sample-tabs/blob/master/src/lib/Stateless.js) and [stateful Tabs](https://github.com/tanqhnguyen/sample-tabs/blob/master/src/lib/Stateful.js), a "hybrid" `Tabs` would be something like this

```html
class HybridTabs extends Component {
  constructor(props) {
    super(props);

    this.state = {
      active: props.active || this.getTabs()[0].props.title
    };
  }

  componentWillReceiveProps(nextProps) {
    this.setState({
      active: nextProps.active
    });
  }

  onSwitchTab(title) {
    this.setState({active: title}, () => {
      this.props.onSwitchTab(title);
    });
  }

  getTabs() {
    return React.Children.toArray(this.props.children).filter(({type}) => {
      return type === Tab;
    });
  }

  render() {
    return (
      <Tabs active={this.state.active}
        onSwitchTab={this.onSwitchTab.bind(this)}>
        {this.props.children}
      </Tabs>
    );
  }
}
```

At first glance, it looks like the example in stateless `Tabs`. It actually is, but with few extra methods to handle `props` changes.

First of all, `constructor` now needs to take into consideration the initially active tab, by getting it from `props.active` or falling back to the default convention which is to use the first `Tab`.

Then, there is this `componentWillReceiveProps` method (if you are not familiar with React or just forget it, you can check it here [componentWillReceiveProps](https://facebook.github.io/react/docs/react-component.html#componentwillreceiveprops)) to update the internal `state` with new `props.active` whenever it's changed (by other components).

Finally, `onSwitchTab` is a combination of setting the internal state and calling `props.onSwitchTab` to notify other components about the change in active tab.

With this hybrid component, I can achieve the goal of using it as a stateless component if things get complicated or as a stateful component for simple tab switching. However, the drawback is that the component itself is quite complex because it needs to handle both internal and external state changes. Also, there are multiple ways of using a hybrid component which can be confusing sometimes in a large codebase.

# Final thoughts
In my opinion, there is no go-to solution. Stateless, stateful or hybrid components have their own strengths and weaknesses. Knowing where and when to use what is the key to solve the problem.

I usually start with a stateless component and if I see a lot of boilerplate code being used because of it, I will turn it into a stateful one. And if there are needs to sometimes use it as a stateless component and sometimes as a stateful component, I will then "upgrade" it to hybrid.

In case you need to see the code, I quickly put together a demo for stateless, stateful and hybrid `Tabs` at [https://github.com/tanqhnguyen/sample-tabs](https://github.com/tanqhnguyen/sample-tabs).
