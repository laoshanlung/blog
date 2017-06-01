+++
date = "2017-05-28T20:45:40+03:00"
title = "Build a simple chat web app using Faye, Express and Vue - Part 4"
tags = ['nodejs', 'express', 'javascript', 'faye', 'vue']
categories = ['Programming']
+++

In the previous part, I implemented a simple pub/sub server to push messages to the client side. In this part, I am going to implement the user interface using [Vue](https://vuejs.org/)

<!--more-->
## Data flow
Vue supports [Flux](https://facebook.github.io/flux/) officially through the use of [Vuex](https://vuex.vuejs.org/en/). There are a lot of blog posts around the Internet explaining Flux pattern in great details, so I won't go deep into it. Instead I will summarize the core concepts of Vuex

Vuex provides a single source of truth (single state tree) where all the changes must go through. UI components change according to changes made to state.

Each change in Vuex happens through a mutation (event). Each mutation modifies the state tree and in turn re-renders the UI accordingly.

```javascript
export default {
  [types.DELETED_MESSAGE] (state, {id}) {
    state.messages = state.messages.filter((msg) => {
      return msg.id !== id
    })
  }  
}
```

Vuex encourages the use of constants for mutation types in order to share them with actions (more on this later). In the above mutation, the state is mutated by filtering out the message matched with `id`.

As mentioned before, actions are a part of the data flow. In Vuex, there is no restriction on how to mutate the data, it can be done through mutations or actions. However, actions are there to separate the mutation logic from the actual action leading to the mutation. For example, when a user clicks the button to send a message, it triggers `sendMessage` action which in turn triggers `sentMessage` mutation after calling the API to notify the UI that there is a new message. If all that happens inside a mutation, it is difficult to test and re-use.

```javascript
export const sendMessage = ({commit}, payload) => {
  api('/messages', {
    method: 'post',
    body: payload
  }).then((message) => {
    commit(types.SENT_MESSAGE, message)
  })
}
```

There are [getters](https://vuex.vuejs.org/en/getters.html) but since they are just normal functions used to get stuff from state, I will skip them.

Vuex also supports [modules](https://vuex.vuejs.org/en/modules.html) which are used to split the state tree into smaller sections for more complicated applications. In this simple chat application, I am not going to use any modules.

All of them are combined into one single `store` and pass to the main application instance

```javascript
new Vue({
  el: '#app',
  router,
  store,
  template: '<App/>',
  components: { App }
})
```

### Mutations
In this chat app, there are 5 types of mutations

```javascript
export default {
  [types.DELETED_MESSAGE] (state, {id}) {
    state.messages = state.messages.filter((msg) => {
      return msg.id !== id
    })
  },

  [types.FETCHED_MESSAGES] (state, messages) {
    state.messages = messages
    state.isFetchingMessages = false
  },

  [types.SENT_MESSAGE] (state, message) {
    addNewMessage(state, message)
  },

  [types.RECEIVED_MESSAGE] (state, message) {
    addNewMessage(state, message)
  },

  [types.FETCHED_ME] (state, me) {
    state.me = me
    state.isFetchingMe = false
  }
}
```

- `DELETED_MESSAGE` is called when a message is deleted either by the current user or someone else
- `FETCHED_MESSAGES` is called when the app receives messages from the API
- `SENT_MESSAGE` is called after sending a new message in order to append the new message to the current message list
- `RECEIVED_MESSAGE` is similar to `SENT_MESSAGE` but this is for when receiving a new message from someone else
- `FETCHED_ME` is called after receiving the data of the current user

### Actions
Corresponding to those mutations are the following actions

```javascript
export const fetchMessages = ({commit}) => {
  api('/messages').then((messages) => {
    commit(types.FETCHED_MESSAGES, messages)
  })
}

export const sendMessage = ({commit}, payload) => {
  api('/messages', {
    method: 'post',
    body: payload
  }).then((message) => {
    commit(types.SENT_MESSAGE, message)
  })
}

export const deleteMessage = ({commit}, payload) => {
  commit(types.DELETED_MESSAGE, {
    id: payload.id
  })
  api(`/messages/${payload.id}`, {
    method: 'delete'
  })
}

export const receivedMessage = ({commit}, payload) => {
  commit(types.RECEIVED_MESSAGE, payload)
}

export const deletedMessage = ({commit}, payload) => {
  commit(types.DELETED_MESSAGE, payload)
}

export const fetchMe = ({commit}, payload) => {
  api('/me', {
    prefix: 'auth'
  }).then((me) => {
    commit(types.FETCHED_ME, me)
  })
}
```

Actions usually follow the same pattern, call the API then commit a mutation based on the data received. However, since this is a chat app receiving data in real-time, there need to be some actions specifically for handling events from faye. For example, when sending a message, the API triggers a faye event

```javascript
faye.publish('/messages', {
  event: 'receivedMessage',
  payload: message
});
```

Then in the UI, I listen to the faye channel and dispatch appropriate actions

```javascript
const client = new Faye.Client(config.get('faye.url'))

client.subscribe('/messages', ({event, payload}) => {
  store.dispatch(event, payload)
})
```

## UI components
Let's take a look at the final UI first

![simple-chat-ui-layout](/images/simple-chat-ui-layout.png)

I usually divide components into 2 categories, presentational and container components. They are also known as stateless and stateful components. Presentational components are responsible for rendering the actual UI, they are often nested inside of another container component. Data is passed down to presentational components by the parent (container) component. Presentational components usually communicate with their parent through the use of events.

There are 4 presentational components in this chat app

- [CurrentUser](https://github.com/tanqhnguyen/simple-chat-web/blob/master/src/components/CurrentUser.vue) renders the info about the current user or a button to log in
- [MessageList](https://github.com/tanqhnguyen/simple-chat-web/blob/master/src/components/MessageList.vue) renders the list of messages
- [Message](https://github.com/tanqhnguyen/simple-chat-web/blob/master/src/components/Message.vue) renders one message
- [MessageInput](https://github.com/tanqhnguyen/simple-chat-web/blob/master/src/components/MessageInput.vue) renders the input for sending a new message

There is only 1 container component [Main](https://github.com/tanqhnguyen/simple-chat-web/blob/master/src/pages/Main.vue) which does all the API calls and manages the state tree. In reality, there might be many container components, each handles one route/path or whatever unit you use to define a single page in the application.

### Components
A component defines an UI element, it can be as simple as an input or as complicated as a list of messages.

A component in Vue is just a normal Javascript object with proper attributes to define the behaviour of the component. Vue borrows the same `props` concept from React to indicate data passed to the component by its parent. There is also `data` which is somewhat similar to `state` in React world. However, when accessing data, Vue doesn't have any distinction between external data and internal data, everything can be accessed through the component instance (`this`). It's convenient for developing but might come and bite me later on when I accidentally change `props`

The style of defining a component in Vue is definitely my favourite. Everything is in one file

```html
<template>

</template>

<script>
import moment from 'moment'
export default {
  name: 'Message',
  props: {
    message: Object,
    me: Object
  }
}
</script>

<style lang="scss" scoped>

</style>
```

Data binding is another strong point of Vue, everything is automatic and is somewhat similar to Angular style

```html
<a class="CurrentUser__card-avatar">
  <img :src="user.avatarUrl" class="CurrentUser__card-avatar-img">
</a>
```

This binds `this.user.avatarUrl` to `src` attribute of `img` tag, every time `avatarUrl` changes, `src` is also updated.

It can go the other way as well (it's often known as 2-way data binding) using `v-model` attribute. This can save a lot of time doing form controls

```
<input @keyup.enter="sendMessage"
       class="input"
       type="text"
       placeholder="Type a message..."
       :disabled="disabled"
       v-model="input">
```

There are a lot more when it comes to component, this blog post probably won't be able to cover everything. So I just write about things that I find interesting and somewhat important to mention.

### Interaction between components
There is one simple rule: "props down, events up", this is true for most frameworks I have a chance to work with (Angular, React, Vue). Events here can mean an actual event fired and forgotten or a function call (in the case of React)

In `MessageInput`, I have this method to emit an event with the message typed by the user. This method is triggered when the user presses "Enter" (`@keyup.enter="sendMessage"`)

```javascript
methods: {
  sendMessage (e) {
    const content = this.input.trim()
    if (!content) return
    this.$emit('send-message', {content})
    this.input = ''
  }
}
```

In the parent component which is `Main`, it listens to `send-message` event

```
<message-input @send-message="sendMessage"
               :disabled="!me"/>
```

and acts accordingly (`me` here refers to the current user). The input is disabled if it's a guest

```javascript
sendMessage ({content}) {
  this.$store.dispatch('sendMessage', {content})
}
```

Passing `props` down is straightforward, in `Main`, when rendering `MessageList`

```
<message-list @delete-message="deleteMessage"
              :messages="messages"
              :me="me" />
```

`messages` is a computed attribute which uses `getMessage` getter in the store to get current messages

```javascript
computed: {
  messages () {
    return this.$store.getters.getMessages()
  }
}
```

## Router
Vue comes with [vue-router](https://github.com/vuejs/vue-router)

```javascript
import Vue from 'vue'
import Router from 'vue-router'
import Main from 'pages/Main'

Vue.use(Router)

export default new Router({
  routes: [
    {
      path: '/',
      name: 'Main',
      component: Main
    }
  ]
})
```

There is only one route in this application, so the setup is very simple.

## Root component
The root component is usually in charge of bootstrapping the whole application. I does the initial request to fetch data, loads all the routes and many other things.

```html
<template>
  <div id="app" class="container">
    <router-view></router-view>
  </div>
</template>

<script>
export default {
  name: 'App',
  mounted: function () {
    this.$store.dispatch('fetchMessages')
    this.$store.dispatch('fetchMe')
  }
}
</script>

<style>
html, body, #app {
  height: 100%;
  background-color: #f5f8fa;
  padding: 10px 0px;
}
</style>
```

## Put everything together
At the root, there is `App` component which loads chat messages and current user data from the API. And at the root path `/`, `Main` component is rendered. It receives a `store` instance created during the [initialization](https://github.com/tanqhnguyen/simple-chat-web/blob/part-4/src/main.js), from `store`, `Main` gets messages and current user data, then passes it down to `MessageList` and `CurrentUser` respectively.

`MessageInput` emits `send-message` event everytime the user presses "Enter" or the button to send the message. `Main` listens to this event and dispatch `sendMessage` action when it happens. The action then sends `POST /api/messages` request to the API to create a new message and commit `SENT_MESSAGE` mutation upon success.

`MessageList` just renders whatever `messages` it receives, each message is a `Message` component. This component also emits `delete-message` event when the user wants to delete a message. This event propagates all the way to `Main` (through `MessageList`). In `Main`, upon receiving this event, it calls `deleteMessage` action which sends a `DELETE /api/messages/:id` request to the API. When it finishes, it commits a `DELETED_MESSAGE` mutation to update the state tree.

That is pretty much everything for this simple chat app. I skip error handling to make everything simpler to follow since this is just a demo application for me to learn Vue.

## Conclusion
There are a lot to talk about Vue, this blog post probably won't/can't cover everything. But my impression about Vue is extremely positive, everything just works, no complicated setup (actually [vue-cli](https://github.com/vuejs/vue-cli) does all the hard works for me)

The source code for this part can be found at [https://github.com/tanqhnguyen/simple-chat-web/tree/part-4](https://github.com/tanqhnguyen/simple-chat-web/tree/part-4)

I also changed `api` and `faye` service to make them work with the UI

- Source code for `api` can be found at [https://github.com/tanqhnguyen/simple-chat-api/tree/part-4](https://github.com/tanqhnguyen/simple-chat-api/tree/part-4)
- Source code for `faye` can be found at [https://github.com/tanqhnguyen/simple-chat-faye/tree/part-4](https://github.com/tanqhnguyen/simple-chat-faye/tree/part-4)

Next, I am going to write about the deployment process. The goal is to deploy this app as 3 separate services (`api`, `faye` and `web`) using `dokku`.
