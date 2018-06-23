+++
date = "2018-06-19T11:52:29+02:00"
title = "Authentication in nuxtjs"
tags = ['nuxtjs', 'javascript']
categories = ['Programming']
+++

I have been watching Vue from the distance for some time, and I have decided to jump into the hype train to take a closer look at Vue and its ecosystem after reading about [nuxtjs](https://nuxtjs.org/). Nuxt is built on top of Vue to make server-side rendering great again. Server-side rendering was a hot topic few years ago. Maybe it has always been hot but I just don't pay attention. Anyway, Nuxt offers a very simple (but powerful) way to do server-side rendering using Vue's infrastructure and components. In this blog post, I am going to describe how I do authentication in nuxt, it's using a different approach than the official [auth example](https://nuxtjs.org/examples/auth-external-jwt)

<!--more-->

## The setup
My imaginary project will have 2 parts, the backend and the frontend. The frontend is Nuxt and the backend can be whatever, it doesn't matter in the context of this blog post. The backend consists of the API and the authentication logic.

The authentication process can be anything, I am using Facebook OAuth2. And there will not be a lot of backend code involved since this is all about nuxt. However, in case I need to show some backend code, it will be Go. Now, let's get started!

## The authentication flow
Basic Facebook authentication is simple, you have a button with Facebook logo and some text to convince people to click it. That part is for the frontend.

Then, after they have clicked the button, we send them to the backend where the actual authentication will happen.

When they have logged in using their Facebook account, they will be redirected to our configured callback url, typical OAuth flow, nothing special here. The function handling this callback endpoint will then create or update the account and set a cookie containing a jwt token generated for the authenticated user. Here is an example

```go
func (handler *JwtHandler) SetJwtToken(account model.Account, w http.ResponseWriter, r *http.Request) *http.Cookie {
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		accountIDField: account.Id,
	})

	tokenString, err := token.SignedString([]byte(config.Current.Auth.Secret))
	if err != nil {
		log.Printf("Failed to sign jwt token: [%s]", err)
		http.Redirect(w, r, "/", http.StatusTemporaryRedirect)
		return nil
	}

	oneDay := time.Hour * 24

	cookie := &http.Cookie{
		Name:     cookieName,
		Value:    tokenString,
		Path:     "/",
		HttpOnly: true,
		MaxAge:   int(oneDay.Seconds()),
	}

	http.SetCookie(w, cookie)

	return cookie
}
```

If everything went smoothly we will have an authenticated session. I particularly like this approach because it shifts the authentication logic completely towards the backend. The frontend doesn't need to know or store any token (still need the cookie in the browser, though).

## Nuxt
Assuming that we have all the cookies and token set correctly, now we need to tell Nuxt to use it when calling the api.

Below is a typical nuxt project, there are some extra files and folders for organizing custom stuff.

![nuxt-structure](/images/nuxt-structure.png)

Nuxt organizes and automatically picks up files from different folders to set up everything for us. For example, each file in `pages` is one route. I will not go into details about Nuxt here because their documentation is very good and covers everything.

The key concept to the authentication flow is `middleware`. A middleware is simply a function that Nuxt will call before rendering a page. Here is the `authenticated` middleware to check whether a session/user is authenticated or not.

```js
import request from '../utils/request';
import errorCode from '../utils/errorCode';
import {
  SET_USER
} from '../utils/actions';

export default async function (context) {
  const {
    store,
  } = context;
  const { get } = request(context);

  if (store.getters.me) return store.getters.me;

  try {
    const res = await get('api/me');
    store.commit(SET_USER, res.data);
    return res;
  } catch (error) {
    if (error.code === errorCode.UNAUTHENTICATED) {
      return context.redirect('/auth');
    }
    throw error;
  }
}
```

`request` is a wrapper around [axios](https://github.com/axios/axios) so that we can switch to a different library if we want to. And `errorCode` is a collection of possible error codes returned by the API. When using Javascript to write the API, this can be a shared module between the frontend and the backend.

`store` is just a normal `vuex` store that Nuxt sets up automatically for us by picking up files in `store` folder. For example, this is the `store/index.js` file.

```js
import {
  SET_USER
} from '../utils/actions';

export const state = () => ({
  me: null,
});

export const mutations = {
  [SET_USER]: (state, me) {
    state.me = me;
  }
};

export const getters = {
  me(state) {
    return state.me ? { ...state.me } : null;
  },
};
```

In case you don't know about [vuex](https://vuex.vuejs.org/), it's a library to manage state in Vue, similar to Redux or other Flux libraries in React world. Here we only use `mutations` and `getters`. Mutation is a mean to mutate the state through a function call. And getter is... a getter, it returns something from the state.

The main part here is how we handle the authentication logic, if we have already had the authenticated user stored, we just return

```js
if (store.getters.me) return store.getters.me;
```

But if we don't have the user stored yet, we need to call the API. Again here, the API is the main actor, it returns the current authenticated user or an error (with the specific code `UNAUTHENTICATED`) if it can't find one. Then if we are sure that the user has been authenticated, we call `store.commit` to store the user data into the state. Otherwise, we just redirect the user to `/auth` which is a normal page with a login button that sends the user to our API to start the authentication flow.

```js
try {
  const res = await get('api/me');
  store.commit(SET_USER, res.data);
  return res;
} catch (error) {
  if (error.code === errorCode.UNAUTHENTICATED) {
    return context.redirect('/auth');
  }
  throw error;
}
```

Then in a page, we need to tell Nuxt to use the `authenticated` middleware. For example, this is the `pages/secret.vue` page

```js
<template>
  <div>
    Secret
  </div>
</template>

<script>
export default {
  middleware: [
    'authenticated',
  ],
};
</script>

<style>

</style>
```

Last but not least, in order to attach the cookie to requests sent to the API, we need to set `withCredentials` to true in `axios`. For other libraries, there should be a similar option to set the credentials for a request. Also, the backend needs to have proper CORS (Cross-Origin Resource Sharing) support, but it's outside the scope of this blog post.

## Logout
The backend handles the logout process, all the frontend needs to do is to call the API. So, what we need is a page with a `fetch` function. Nuxt will call this function to fullfil the data required for rendering the page, but it can also be used to log the user out of the system.

```js
<template>
  <div>Nothing to see here</div>
</template>

<script>
import request from '../utils/request';
import {
  SET_USER
} from '../utils/actions';

export default {
  layout: 'noNavBar',
  async fetch(context) {
    const { get } = request(context);
    await get('auth/logout');
    context.store.commit(SET_USER, null);
    context.redirect('/');
  },
};
</script>

<style scoped>
.hero.is-success {
  background-color: #F2F6FA;
}
</style>
```

And that's it, it's how I do authentication in Nuxt. It is not the most secured way to do authentication but it works well with my imaginary and small projects.
