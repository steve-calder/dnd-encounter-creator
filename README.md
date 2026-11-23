# D&D Encounter Creator

A Rails 8 app backed by MongoDB (via Mongoid), with MongoDB Vector Search for
similarity queries over embeddings.

## Prerequisites

- Ruby 4.0.10 (see `.ruby-version`)
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

3. **Load the monster catalog** (see [Monster catalog](#monster-catalog)):

   ```sh
   bin/rails db:mongoid:create_indexes
   bin/rails catalog:import
   ```

4. Open <http://localhost:3000> to browse the catalog. The health check is at
   <http://localhost:3000/up>.

## Monster catalog

The catalog ships in the repo as
[db/data/srd_monsters.json](db/data/srd_monsters.json): the 379 System
Reference Document (SRD) monsters from the Free Basic Rules (2014) and Free
Basic Rules (2024). Only these records have complete stat blocks in the
upstream dataset. Its `source` header records where the records came from:

| Field          | Value                                                              |
| -------------- | ------------------------------------------------------------------ |
| `repository`   | `nick-aschenbach/dnd-data`                                         |
| `commit`       | `649f7f964b20835852bff3659aa36875dd7c35df`                         |
| `path`         | `data/monsters.json`                                               |
| `sha256`       | `cee519309b7241ed6cd45b2217f9e37e481d451aa3fd9ce251dfbd7a4ef302c7` |
| `books`        | `Free Basic Rules (2014)`, `Free Basic Rules (2024)`               |
| `record_count` | `379`                                                              |

Import it into MongoDB with:

```sh
bin/rails catalog:import
```

The import reads only the committed file and needs no network. It is safe to
rerun: records are matched by stable ID (such as `srd-2014--giant-shark`), and
unchanged records are skipped. It prints a report of created, updated, and
unchanged records, plus how many are eligible for encounter generation. The 7
spell-summon records with no challenge rating are kept but marked ineligible.

### Regenerating the dataset

Don't edit `db/data/srd_monsters.json` by hand. To regenerate it, for example
after changing the pinned commit or the `BOOKS` list in the script, run:

```sh
script/extract_srd_monsters.rb                         # downloads the pinned upstream file
script/extract_srd_monsters.rb path/to/monsters.json   # or uses a local copy
```

The script is for development only. It verifies the upstream SHA-256 before
writing and produces byte-identical output for the same input. The import,
tests, and CI never run it.

Monster data is from the System Reference Document 5.1 and 5.2 by Wizards of
the Coast LLC, licensed under
[CC-BY-4.0](https://creativecommons.org/licenses/by/4.0/legalcode).

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
When tests run in parallel, each worker uses its own copy
(`dnd_encounter_creator_test-0`, `-1`, and so on).

To run the full local CI suite (tests, RuboCop, and security scans):

```sh
bin/ci
```
