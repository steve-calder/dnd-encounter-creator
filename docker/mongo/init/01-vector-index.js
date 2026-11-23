// Runs once, on first startup with an empty data volume.
// Creates the monsters collection with a vector search index.
//
// The vector size comes from EMBEDDING_DIMENSIONS (set in compose.yaml) and must
// match the embedding model's output size, e.g. 768 for Ollama's nomic-embed-text,
// 1024 for mxbai-embed-large. Changing it requires recreating the data volume.

const dbName = process.env.MONGODB_INITDB_DATABASE || "dnd_encounter_creator_development";
const appDb = db.getSiblingDB(dbName);

const numDimensions = parseInt(process.env.EMBEDDING_DIMENSIONS || "768", 10);
if (!Number.isInteger(numDimensions) || numDimensions <= 0) {
  throw new Error(`EMBEDDING_DIMENSIONS must be a positive integer, got "${process.env.EMBEDDING_DIMENSIONS}"`);
}

if (!appDb.getCollectionNames().includes("monsters")) {
  appDb.createCollection("monsters");
}

appDb.monsters.createSearchIndex(
  "monsters_vector_index",
  "vectorSearch",
  {
    fields: [
      { type: "vector", path: "embedding", numDimensions, similarity: "cosine" },
      { type: "filter", path: "challenge_rating" },
      { type: "filter", path: "environment" }
    ]
  }
);

print(`Created vector search index on ${dbName}.monsters (${numDimensions} dimensions)`);
