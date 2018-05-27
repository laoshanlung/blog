+++
date = "2018-05-20T11:52:29+02:00"
title = "Use postgresql for authorization layer"
tags = ['postgresql']
categories = ['Programming']
+++

Postgresql is my favorite relational database. There are a lot of cool things that Postgresql can do and one of those is to handle the authorization layer. Some people argue that putting authorization logic into the database makes the application code harder to read, and that's actually true if there is only 1 code base connecting to a database. However, if there are more than 1 code bases communicating with a database, having a centralized authorization logic starts to make more sense. In this blog post, I am not going to discuss the pros and cons of having the authorization logic inside the database, but instead I am going to describe how I put all my authorization logic into postgresql.

<!--more-->

This blog post assumes that you have prior knowledge about postgresql and SQL in general.

## Basic concepts
There are some basic concepts that we need to know before continuing

### Role
A role in postgresql can mean many things. It can be an user, a group of users. I usually think role as a group of users. For example, in a forum, there are normal users, moderators and admins. A new role can be created by [CREATE ROLE](https://www.postgresql.org/docs/current/static/sql-createrole.html). For example

```sql
CREATE ROLE anonymous;
```

Then, to change the role of the current connection, simply call

```sql
SET ROLE anonymous;
```

### Table privileges
In postgresql, we can control which role can access which table. This is done via `GRANT`. For example

```sql
GRANT ALL ON forum TO admin;
```

This allows admin to do ALL operations on `forum` tables.

### Column privileges
Next we have column privileges. These are more granular and for controlling how roles can access columns in a table. This is also done via `GRANT`. For example

```sql
GRANT SELECT(name) ON forum TO anonymous;
```

This restricts `anonymous` role from accessing other columns in `forum` than `name`. So doing `SELECT * FROM forum` will return an error.

### Row-level security
This is the lowest (and most powerful) level that controls the access to a specific row. This is called `policy` in postgresql and can be created by [CREATE POLICY](https://www.postgresql.org/docs/current/static/sql-createpolicy.html). However, row-level security is not enabled by default, so we need to manually enable it if we want to use it

```sql
ALTER TABLE forum ENABLE ROW LEVEL SECURITY;
```

Row-level security is a bit more complicated subject. For the sake of this post, I am not going to explain every bit of the syntax but instead just show the queries and explain what they do.

A policy is tied to a role, and defines what that role can do (SELECT, UPDATE, DELETE, INSERT) to a row. For example

```sql
CREATE POLICY moderator_can_update_forum ON forum  
FOR UPDATE
WITH CHECK(current_user = 'moderator');
```

This allows `moderator` to do `UPDATE` operations, all other roles can't do that if not specifically set so. However, `moderator` still needs to be granted `UPDATE` on `forum` table

```sql
GRANT UPDATE ON forum TO moderator;
```

## Putting everything together
I am going to design a database schema for a simple project where you can create your own store and display some products on your store. Here is the database schema

```sql
CREATE TABLE account (
  id SERIAL PRIMARY KEY,
  username VARCHAR(32) NOT NULL,
  password TEXT NOT NULL,
  phone_number TEXT NOT NULL,
  role VARCHAR(16) NOT NULL
);

ALTER TABLE account ADD CONSTRAINT unique_username UNIQUE(username);
ALTER TABLE account ENABLE ROW LEVEL SECURITY;

CREATE TABLE store (
  id SERIAL PRIMARY KEY,
  name VARCHAR(64) NOT NULL,
  description TEXT,
  rank INT DEFAULT -1,
  owner_id INT NOT NULL REFERENCES account(id) ON DELETE CASCADE
);
ALTER TABLE store ENABLE ROW LEVEL SECURITY;

CREATE TABLE product (
  id SERIAL PRIMARY KEY,
  name VARCHAR(128) NOT NULL,
  stock INT DEFAULT 0,
  description TEXT,
  store_id INT NOT NULL REFERENCES store(id) ON DELETE CASCADE
);
ALTER TABLE product ENABLE ROW LEVEL SECURITY;
```

Next, we need to have some roles for the project

```sql
CREATE ROLE super_admin;
CREATE ROLE store_owner;
CREATE ROLE normal_account;

GRANT normal_account TO store_owner;
GRANT store_owner TO super_admin;
```
- `normal_account` is ... just a normal account in our app
- `store_owner` is the creator of a store. So for the sake of simplicity, any normal account who created a store is automatically promoted to a `store_owner` 
- `super_admin` can basically do anything, it's usually us who manages the project

The last 2 `GRANT` queries establish a chain of privileges, `store_owner` can do anything that `normal_account` can do. And `super_admin` can do anything that `store_user` can do. In reality, it might be possible to have a deeper user role hierarchy.

Now, let's define the permissions for each role. Let's do it for `normal_account` and `store_owner` because `super_admin` can do absolutely anything. In addition to explicitly define the permissions for `super_admin`, I can also set `BYPASSRLS` when creating the role in order to bypass all the row-level security.

### account
For this table, no one can INSERT or DELETE except `super_admin` and since `store_owner` is also a `normal_account`, let's define what a `normal_account` can do.

```sql
GRANT SELECT ON account TO normal_account;
GRANT UPDATE ON account TO normal_account;
```

This allows `normal_account` to SELECT and UPDATE all columns in `account` table. But it's not enough, we must limit it so that an account can only UPDATE their own data and not everyone else's. For SELECT, we probably want the same limitation because leaking other people data is obviously bad.

```sql
CREATE POLICY normal_account_can_update_their_account ON account
FOR UPDATE
TO normal_account
WITH CHECK (is_current_account(id));

CREATE POLICY normal_account_can_select_their_account ON account
FOR SELECT
TO normal_account
USING (is_current_account(id));
```

The 2 queries are straightforward, we have just created 2 policies in `account` table to control the visibility of its rows. The only new bit here is `is_current_account(id)` function. First, let's take a look at its source code.

```sql
CREATE OR REPLACE FUNCTION is_current_account(account_id integer)
RETURNS BOOLEAN
AS $$
DECLARE
  current_account_id INT;
  owner_id INT;
BEGIN
  SELECT current_setting('auth.current_account_id', true)::int INTO current_account_id;
  RETURN current_account_id = account_id;
END;
$$ LANGUAGE plpgsql;
```

For those who don't like `plpgsql`, you can switch to Javascript to write stored procedures using this extension [https://github.com/plv8/plv8](https://github.com/plv8/plv8). For this blog post, I will stick to the default language.

This simple function checks if the provided value (account_id) matches the current account id stored in `auth.current_account_id` setting (Need to have some prefix, or postgresql will try to set the server config). This leads to the next point: **How do we set the current account in postgresql?**

There are several ways to do that, you can have a simple function `login(username, password)` to select the account matched the provided username and compare the password, just like a regular login flow. Then if everything is correct, set the role and store the account id in `auth.current_account_id` setting through this query

```sql
SELECT set_config('auth.current_account_id', account.id::text, true);
```

Set the last parameter to `true` to apply this config for the current transaction, and `false` for the current session. This value depends on your application layer's logic. The 2nd parameter needs to be a string because of the function signature.

In reality, we **SHOULD AVOID** setting an actual (id) value to `current_account_id`. There should be some kind of encryption so that people can't just call `set_config` and bypass the login process.

Anyway, for the sake of simplicity, I will just manually set the role, and `current_account_id` to whatever I want in order to demonstrate the permission system.

And last but not least, we need to allow `super_admin` to do anything in `account` table, simply pass `true` to USING and WITH CHECK.

```sql
GRANT INSERT, DELETE ON account TO super_admin;
CREATE POLICY super_admin_can_do_anything ON account
FOR ALL
TO super_admin
USING (true)
WITH CHECK (true);
```

Then, there is one last thing which is to allow `admin` to use the primary key (id) sequence. Without this, `admin` won't be able to generate the next id to be used as the primary key for the new row.

```sql
GRANT ALL ON account_id_seq TO super_admin;
```

### store
Our `store` table has the following schema

```sql
CREATE TABLE store (
  id SERIAL PRIMARY KEY,
  name VARCHAR(64) NOT NULL,
  description TEXT,
  rank INT DEFAULT -1,
  owner_id INT NOT NULL REFERENCES account(id) ON DELETE CASCADE
);
```

Assuming that `rank` is only visible to the `store_owner`, we have these GRANT queries. And `store_owner` can only UPDATE name and description. The column `rank` could be something we do in a background job to let store owners know how well their store is doing.

```sql
GRANT SELECT(id, name, description) ON store TO normal_account;
GRANT SELECT(rank, owner_id) ON store TO store_owner;
GRANT UPDATE(name, description) ON store TO store_owner;
GRANT ALL ON store TO super_admin;
GRANT ALL ON store_id_seq TO super_admin;
```

Similar to `account` table, we still need to have some policies. `normal_account` can SELECT all the stores and `store_owner` can only UPDATE their own store. Also, `super_admin` can do anything here as well.

```sql
CREATE POLICY normal_account_can_select_everything ON store
FOR SELECT
TO normal_account
USING (true);

CREATE POLICY store_owner_can_update_their_store ON store
FOR UPDATE
TO store_owner
WITH CHECK (is_current_account(owner_id));

CREATE POLICY super_admin_can_do_anything ON store
FOR ALL
TO store_owner
USING (true)
WITH CHECK (true)
```

However, there is one problem with this table, we don't want one store owner to see the rank of another store. With our role hierarchy, `normal_account` can SELECT all the rows which means that `store_owner` can also SELECT all the rows (including the `rank` column).

We can't revoke access to `rank` column because we still want the store owner to see their own rank. And postgresql doesn't support anything to "hide" a column value.

The only solution I can come up with to deal with this limitation is to move `rank` to another table, say, `store_rank` and we can apply row level security there to only allow the store owner to SELECT their rank.

### product
Our `product` table has the following schema

```sql
CREATE TABLE product (
  id SERIAL PRIMARY KEY,
  name VARCHAR(128) NOT NULL,
  stock INT DEFAULT 0,
  description TEXT,
  store_id INT NOT NULL REFERENCES store(id) ON DELETE CASCADE
);
```

Alright, I am going quicker here since the permission is (almost) the same as that of the `store` table

```sql
GRANT SELECT ON store TO normal_account;
GRANT UPDATE(name, stock, description) ON store TO store_owner;
GRANT INSERT ON store TO store_owner;
GRANT SELECT, USAGE ON store_id_seq TO store_owner;
GRANT DELETE ON store TO store_owner;

GRANT ALL ON store TO super_admin;
GRANT ALL ON store_id_seq TO super_admin;
```

The only different bit here is the INSERT and DELETE permission. We allow store owners to create and delete products on their store. And that leads to the following policies to accompany the above privileges.

```sql
CREATE POLICY   normal_account_can_select_everything ON product
FOR SELECT
TO normal_account
USING (true);

CREATE POLICY store_owner_can_update_their_product ON product
FOR UPDATE
TO store_owner
WITH CHECK (is_store_owner(store_id));

CREATE POLICY store_owner_can_delete_their_product ON product
FOR DELETE
TO store_owner
USING (is_store_owner(store_id));

CREATE POLICY store_owner_can_insert_product_to_their_store ON product
FOR INSERT
TO store_owner
WITH CHECK (is_store_owner(store_id));

CREATE OR REPLACE FUNCTION is_store_owner(store_id integer)
RETURNS BOOLEAN
AS $$
DECLARE
  owner_id INT;
BEGIN
  SELECT owner_id FROM store WHERE id = store_id INTO owner_id;
  RETURN is_current_account(owner_id);
END;
$$ LANGUAGE plpgsql;
```

## Testing
After we have had everything, it's time to make sure it actually works. I am going to insert the following accounts so that we can have something to query. The other tables should behave the same

```sql
INSERT INTO account(username, password, phone_number, role)
VALUES
('storeowner1', 'secret', '123-456-7890', 'store_owner'),
('storeowner2', 'secret', '123-456-7891', 'store_owner'),
('guest1', 'secret', '123-456-7892', 'normal_account'),
('guest2', 'secret', '123-456-7893', 'normal_account'),
('me', 'secret', '123-456-0000', 'super_admin');
```

`super_admin` can select everything

```
tannguyen=# set role super_admin;
SET
tannguyen=> select * from account;
 id |  username   | password | phone_number |      role
----+-------------+----------+--------------+----------------
  1 | storeowner1 | secret   | 123-456-7890 | store_owner
  2 | storeowner2 | secret   | 123-456-7891 | store_owner
  3 | guest1      | secret   | 123-456-7892 | normal_account
  4 | guest2      | secret   | 123-456-7893 | normal_account
  5 | me          | secret   | 123-456-0000 | super_admin
(5 rows)
```

`normal_account` can only see their account. And `store_owner` has the same permission.

```
tannguyen=# set role normal_account;
SET
tannguyen=> select set_config('auth.current_account_id', '3', false);
 set_config
------------
 3
(1 row)

tannguyen=> select * from account;
 id | username | password | phone_number |      role
----+----------+----------+--------------+----------------
  3 | guest1   | secret   | 123-456-7892 | normal_account
(1 row)
```

Both `normal_account` and `store_owner` can only update their own account.

```
tannguyen=# set role store_owner;
SET
tannguyen=> select set_config('auth.current_account_id', '2', false);
 set_config
------------
 2
(1 row)

tannguyen=> update account set password = 'new' where id = 1;
UPDATE 0
```

And of course they can't DELETE or INSERT anything. Continue from the above example

```
tannguyen=> insert into account(username, password, phone_number, role) values ('new', 'new', 'new', 'super_admin');
ERROR:  permission denied for relation account
tannguyen=> delete from account where id = 1;
ERROR:  permission denied for relation account
```

Normally, in a real project, the queries to `SET ROLE` and `set_config` and subsequent queries are wrapped inside a transaction.

There are few things to note here
- `set_config` takes a string instead of int, that's totally normal because of the function syntax. And that doesn't affect the outcome since postgresql automatically converts the type if needed.
- For row-level security, when a role doesn't have sufficient permission, there are no errors. The query still returns an empty result. However, for table and column level, it throws an error.

## Conclusion 
This kind of authorization can be very powerful if using correctly. I lied when I said that I am not going discuss the pros and cons of having postgresql handled the authorization process. I actually have some thoughts about the pros and cons while writing the blog post.

One advantage that I can see from pushing the authorization logic to the database is that it makes the application code more flexible. If for some reason, I decide that I want to switch to something else, I don't have to rewrite the whole authorization logic since it's already there in the database. Switching to another database, on the other hand, is a different story.

Also, having the authorization logic in the database enables the use of multiple services in different languages. With the increasing of microservices architecture, this approach removes the burden of having to duplicate the authorization logic everywhere (one can also centralize the authorization logic in one service to avoid that, but it's another thing, I would rather not discuss it here).

That being said, "hiding" the authorization logic in the database makes it less obvious to the developers. If they don't know about it or simply forget, it might take a lot of time to figure out what happens when having a bug (been there, done that). It also makes it harder for new junior developers to wrap their head around the whole concept (if they are not familiar with postgresl).
