import { extractMarkdownBlocks } from './cdi.js';

const STOP_WORDS = new Set([
  'a', 'about', 'above', 'after', 'again', 'against', 'all', 'am', 'an', 'and', 'any', 'are', 'as',
  'at', 'be', 'because', 'been', 'before', 'being', 'below', 'between', 'both', 'but', 'by', 'could',
  'did', 'do', 'does', 'doing', 'down', 'during', 'each', 'few', 'for', 'from', 'further', 'had',
  'has', 'have', 'having', 'he', 'her', 'here', 'hers', 'herself', 'him', 'himself', 'his', 'how',
  'i', 'if', 'in', 'into', 'is', 'it', 'its', 'itself', 'just', 'me', 'more', 'most', 'my', 'myself',
  'no', 'nor', 'not', 'now', 'of', 'off', 'on', 'once', 'only', 'or', 'other', 'our', 'ours', 'ourselves',
  'out', 'over', 'own', 'same', 'she', 'should', 'so', 'some', 'such', 'than', 'that', 'the', 'their',
  'theirs', 'them', 'themselves', 'then', 'there', 'these', 'they', 'this', 'those', 'through', 'to',
  'too', 'under', 'until', 'up', 'very', 'was', 'we', 'were', 'what', 'when', 'where', 'which', 'while',
  'who', 'whom', 'why', 'with', 'would', 'you', 'your', 'yours', 'yourself', 'yourselves'
]);

/**
 * Tokenizes text into normalized words, filtering out common stop words.
 * @param {string} text
 * @returns {string[]}
 */
export function tokenize(text) {
  if (!text) return [];
  const words = text
    .toLowerCase()
    .replace(/[^a-z0-9_\-\s]/g, ' ')
    .split(/\s+/)
    .filter(w => w.length > 1 && !STOP_WORDS.has(w));

  return words;
}

/**
 * Computes BM25 relevance scores for a collection of documents given a search query.
 * @param {string} query
 * @param {Array<{ id: string, text: string, tier?: string, provenance?: string[] }>} documents
 * @param {number} [k1=1.2]
 * @param {number} [b=0.75]
 * @returns {Array<{ document: any, score: number, matched_terms: string[] }>}
 */
export function rankDocumentsBM25(query, documents, k1 = 1.2, b = 0.75) {
  const queryTokens = tokenize(query);
  if (queryTokens.length === 0 || documents.length === 0) {
    return [];
  }

  const N = documents.length;
  let totalLength = 0;
  const docTokensList = [];
  const docTermFreqs = [];
  const docFreq = new Map(); // term -> number of docs containing term

  for (let i = 0; i < N; i++) {
    const tokens = tokenize(documents[i].text);
    docTokensList.push(tokens);
    totalLength += tokens.length;

    const tf = new Map();
    for (const t of tokens) {
      tf.set(t, (tf.get(t) || 0) + 1);
    }
    docTermFreqs.push(tf);

    for (const t of tf.keys()) {
      docFreq.set(t, (docFreq.get(t) || 0) + 1);
    }
  }

  const avgdl = totalLength / N || 1;

  // Pre-calculate IDF for query terms
  const idf = new Map();
  for (const q of queryTokens) {
    const n_q = docFreq.get(q) || 0;
    // Standard Lucene/BM25 IDF formula
    const val = Math.log(1 + (N - n_q + 0.5) / (n_q + 0.5));
    idf.set(q, Math.max(val, 0.05));
  }

  const scoredResults = [];

  for (let i = 0; i < N; i++) {
    const doc = documents[i];
    const tf = docTermFreqs[i];
    const docLen = docTokensList[i].length;
    let score = 0;
    const matched = [];

    for (const q of queryTokens) {
      const f = tf.get(q) || 0;
      if (f > 0) {
        matched.push(q);
        const termIdf = idf.get(q) || 0;
        const numerator = f * (k1 + 1);
        const denominator = f + k1 * (1 - b + b * (docLen / avgdl));
        score += termIdf * (numerator / denominator);
      }
    }

    // Apply architectural tier & provenance boosts
    if (score > 0) {
      // Credibility boost for anchored blocks with verified provenance
      if (doc.provenance && doc.provenance.length > 0) {
        score *= 1.20;
      }
      // Authoritative boost for T1 contracts and accepted ADRs
      if (doc.tier === 'T1' || doc.tier === 'T0') {
        score *= 1.15;
      }

      scoredResults.push({
        document: doc,
        score: Number(score.toFixed(4)),
        matched_terms: Array.from(new Set(matched))
      });
    }
  }

  // Sort descending by score
  return scoredResults.sort((a, b) => b.score - a.score);
}
