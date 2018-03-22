+++
date = "2018-01-20T11:52:29+02:00"
title = "Build a 2048 game engine"
tags = ['javascript', 'nodejs', 'game']
categories = ['Programming']
+++

Although the game 2048 is not a hot stuff like it used to be several years ago, I am still playing it once in a while. And now I thought that maybe I could try to implement it by myself just to do something else other than web development.

<!--more-->

## Introduction
For those who are not familiar with 2048, it is a puzzle game made by [Gabriele Cirulli](https://gabrielecirulli.com/). I am going to borrow his ideas/concepts and implement my own version of 2048. It's only for fun without any commercial intention or competition with his [original game](https://gabrielecirulli.github.io/2048/).

All of the code that I am going to use is my own code and I do not take any of his original code. I simply play the game, and try to replicate it using my own knowledge gained through playing the game.

## The game engine
The engine is the heart of the whole game, it contains all the logic to handle different movements (left, right, up, down) happened during a game session.

### Storing tiles
At first, I thought that I could use a 2D array to store the tiles and their number. The coordinate starts from the top left of the board (0,0) and runs all the way down to the bottom right (3,3). For example

```js
const tiles = [
  [null, 2, 4, null],
  [null, 2, 8, null],
  [null, 2, null, 16],
  [null, null, null, null],
];
```

It certainly works, but iterating through a 2D array is a pain in the ear. Another reason is that I am really bad at it, I can't never do it right in one try. Therefore, I tend to avoid using 2D arrays if not absolutely necessary. Using Map is the next thing coming to my mind.

```js
const tiles = {
  '0-0': null,
  '0-1': 2,
  '0-2': 4,
  '0-3': null,

  '1-0': null,
  '1-1': 2,
  '1-2': 8,
  '1-3': null,

  '2-0': null,
  '2-1': 2,
  '2-2': null,
  '2-3': 16,

  '3-0': null,
  '3-1': null,
  '3-2': null,
  '3-3': null
};
```

By using the new [Map API](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Map) I can easily travel through all the tiles. However, I might need to know the current location (x, y) of a tile, there are 2 ways to support that, I can either store `{x, y, number}` inside the map or turn it back to an array with each element is an object `{x, y, number}`. A Map with objects is better because I can access the exact tile using its key (`1-1` for example).

```js
const DEFAULT_SIZE = 4;
class Engine {
  constructor(width = DEFAULT_SIZE, height = DEFAULT_SIZE) {
    this.width = width;
    this.height = height;

    this.tiles = new Map();
    for (let y = 0; y < this.height; y++) {
      for (let x = 0; x < this.width; x++) {
        const index = this.tileIndex(x, y);
        const tile = {
          x, y, value: null
        };
        this.tiles.set(index, tile);
      }
    }
    this.states = [];
  }

  tileIndex(x, y) {
    return `${x}-${y}`;
  }
}
```

First thing first, I need to initialize the Map. It has a total of 16 tiles (4x4) and each tile is an object with 3 properties `{x, y, value}`. The key for each tile is constructed using this format `x-y`.

## Movements
There are 4 directions (left, right, up and down) toward which the tiles can move. For each direction, all the tiles move toward that direction and "merge" if they have the same value. For example

This is the original state
```
[ 2][ 2][  ][  ]
[  ][ 2][ 4][  ]
[  ][ 8][  ][  ]
[  ][  ][  ][  ]
```

After moving left, it becomes
```
[ 4][  ][  ][  ]
[ 2][ 4][  ][  ]
[ 8][  ][  ][  ]
[  ][  ][  ][  ]
```

Then, after moving up, it becomes
```
[ 4][ 4][  ][  ]
[ 2][  ][  ][  ]
[ 8][  ][  ][  ]
[  ][  ][  ][  ]
```

Below is the main method used to move tiles toward a direction. It returns an array of moved tiles so that I can do some fancy moving animation for the UI later

```js
move(direction) {
  const tiles = [...this.tiles.values()];

  if ([
    'right',
    'down'
  ].indexOf(direction) !== -1) tiles.reverse();

  return tiles.map((tile) => {
    const destination = this.moveTile(tile, direction);
    if (!destination) return null;
    if (destination.x === tile.x
      && destination.y === tile.y) return null;
    return {
      from: tile,
      to: destination
    };
  }).filter(Boolean);
}
```

The `tiles` map is converted into an array of tiles, each tile will be moved using the logic provided by `moveTile`. For `left` and `up`, it moves from the first element (top left corner) till the last one (bottom right corner). For `right` and `down`, it goes from the last element (bottom right) till the first one (top left corner).

```js
const DIRECTIONS = {
  left(x, y) {
    return {
      x: x - 1,
      y
    };
  },
  right(x, y) {
    return {
      x: x + 1,
      y
    };
  },
  up(x, y) {
    return {
      x,
      y: y - 1
    };
  },
  down(x, y) {
    return {
      x,
      y: y + 1
    };
  }
}

moveTile(thisTile, direction) {
  if (!thisTile || thisTile.value === null) return null;
  const prevTilePos = DIRECTIONS[direction](thisTile.x, thisTile.y);
  const prevTile = this.getTile(prevTilePos.x, prevTilePos.y);

  if (prevTile) {
    if (prevTile.value === null) {
      prevTile.value = thisTile.value;
      thisTile.value = null;
      return this.moveTile(prevTile, direction);
    } else if (prevTile.value === thisTile.value) {
      prevTile.value = thisTile.value * 2;
      thisTile.value = null;
      return prevTile;
    }
  }

  return thisTile;
}
```

This is a simple recursive function to move one tile toward one direction one step at a time. The destination depends on the direction. For example

- When moving `left`, it moves the tile to the left side (x - 1, same y)
- When moving `right`, it moves the tile to the right side (x + 1, same y)
- When moving `up`, it moves the tile to the top side (same x, y - 1)
- When moving `down`, it moves the tile to the bottom side (same x, y + 1)

At first, `up` and `down` seem to be incorrectly reversed. However, it's totally correct because the starting tile is (0, 0) which is the top left of the board. Moving down means that `y` is increasing. Additionally, I encapsulate the whole moving logic into separate functions and put them in `DIRECTIONS` to make it easier to read and change.

The merging logic is also straightforward, if the destination is empty, set its value to the current tile's value. If the destination has the same value as that of the current tile, combine them. And in both cases, set the value of the current tile to `null` (empty). Also, the movement stops immediately after merging 2 tiles having the same value.

There is one missing step in `moveTile` which is to generate random tiles filled with values after each move. And that step is even simpler than moving tiles, just pick 1 or 2 random and empty tiles and fill them with either `2` or `4`. Actually, I am not sure if there is anything more complex behind that or it's just random. But in this simple implementation, I assume that they appear randomly.

## Loss condition
I think in this game, you lose when you can't move tiles anymore. It can be verified by checking if the engine can fill any random tiles AND are there any tiles that moved. I will work on this more after having everything else.

The full source code can be found here [https://github.com/tanqhnguyen/2048-engine](https://github.com/tanqhnguyen/2048-engine)

## CLI!!!
I also add a simple CLI to play the game, just for the fun of it (and also for testing!). You can run it by `npm start`

WARNING! It looks horrible

![2048-cli](/images/2048-cli.png)

