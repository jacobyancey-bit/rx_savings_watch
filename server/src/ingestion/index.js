const { ingestRxNorm } = require('./rxnorm');
const { ingestOrangeBook } = require('./orange_book');
const { ingestPurpleBook } = require('./purple_book');
const { ingestOpenFdaNdc } = require('./openfda_ndc');
const { ingestCmsNadac } = require('./cms_nadac');
const { ingestFdaShortages } = require('./fda_shortages');

/**
 * Coordinate ingestion across all 6 feeds
 * @param {import('node:sqlite').DatabaseSync} db
 * @param {object} [options]
 * @returns {Promise<object>} Summary of ingested records per feed
 */
async function runAllIngestions(db, options = {}) {
  const results = {};

  // 1. RxNorm / RxNav (Core concept foundation)
  results.rxnorm = await ingestRxNorm(db, options.rxnorm);

  // 2. FDA Orange Book (Small molecule generic approvals / ANDA)
  results.orange_book = await ingestOrangeBook(db, options.orange_book);

  // 3. FDA Purple Book (Biologic & biosimilar approvals / BLA)
  results.purple_book = await ingestPurpleBook(db, options.purple_book);

  // 4. OpenFDA NDC Directory (Commercial listing records)
  results.openfda_ndc = await ingestOpenFdaNdc(db, options.openfda_ndc);

  // 5. CMS NADAC (Wholesale acquisition pricing data)
  results.cms_nadac = await ingestCmsNadac(db, options.cms_nadac);

  // 6. FDA Drug Shortages
  results.fda_shortages = await ingestFdaShortages(db, options.fda_shortages);

  return results;
}

module.exports = {
  runAllIngestions,
  ingestRxNorm,
  ingestOrangeBook,
  ingestPurpleBook,
  ingestOpenFdaNdc,
  ingestCmsNadac,
  ingestFdaShortages
};
