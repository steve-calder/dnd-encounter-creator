# D&D Encounter Creator

A Rails 8 app backed by MongoDB (via Mongoid), with MongoDB Vector Search for
similarity queries over embeddings.

## Prerequisites

- Ruby 4.0.9 (see `.ruby-version`)
- Bundler
- Docker with Docker Compose

## Getting started

1. **Start MongoDB** in the background:

   ```sh
   docker compose up -d --wait
   ```

   `--wait` returns once the container is healthy. This runs the
   `mongodb/mongodb-atlas-local` image, which includes the search engine needed
   for `$vectorSearch` queries and vector search indexes.

2. **Install dependencies and start the server:**

   ```sh
   bin/setup
   ```

   This installs gems, clears logs and temp files, and starts the app.
   On later runs, start the server with `bin/dev`.

3. Open <http://localhost:3000>. The health check is at
   <http://localhost:3000/up>.

## Configuration

The app and the container share these environment variables. The defaults
work out of the box. To override them, put them in a `.env` file in the
project root (it is gitignored) or export them in your shell.

| Variable         | Default                             | Used by                             |
| ---------------- | ----------------------------------- | ----------------------------------- |
| `MONGO_USERNAME` | `admin`                             | container and Rails                 |
| `MONGO_PASSWORD` | `admin`                             | container and Rails                 |
| `MONGO_PORT`     | `27017`                             | container and Rails                 |
| `MONGO_HOST`     | `localhost`                         | Rails                               |
| `MONGO_DATABASE` | `dnd_encounter_creator_development` | container (database the init script sets up) |
| `EMBEDDING_DIMENSIONS` | `768` | container (vector index size; see below) |

Docker Compose reads `.env` automatically; Rails does not, so export the
variables in your shell too if you change them. The username and password take
effect only when the database volume is first created; after changing them,
recreate the database (see below).

The defaults are for local development only. Don't reuse them anywhere else.

To connect with a MongoDB client such as `mongosh` or Compass, use:

```
mongodb://admin:admin@localhost:27017/?directConnection=true&authSource=admin
```

Keep `directConnection=true`. The container is a single-node replica set that
advertises the hostname `mongodb`, which your machine can't resolve.

## Vector search

On first startup with an empty database, the container runs
[docker/mongo/init/01-vector-index.js](docker/mongo/init/01-vector-index.js).
It creates a `monsters` collection with a vector search index named
`monsters_vector_index`:

- `embedding`: a vector of `EMBEDDING_DIMENSIONS` numbers (default 768)
  compared by cosine similarity
- `challenge_rating` and `environment`: fields you can filter on

`EMBEDDING_DIMENSIONS` must match your embedding model's output size. The
default, 768, fits Ollama's `nomic-embed-text`; `mxbai-embed-large` needs 1024.
To change it, set the variable (for example in `.env`) and recreate the database
so the index is rebuilt.

## Managing the database

```sh
docker compose ps          # status
docker compose logs -f     # follow logs
docker compose down        # stop; data is kept in Docker volumes
docker compose down -v     # stop and delete all data and indexes
```

To recreate the database from scratch, which reruns the init script:

```sh
docker compose down -v && docker compose up -d --wait
```

## Running tests

With MongoDB running:

```sh
bin/rails test
```

Tests use the `dnd_encounter_creator_test` database on the same container.

To run the full local CI suite (tests, RuboCop, and security scans):

```sh
bin/ci
```
