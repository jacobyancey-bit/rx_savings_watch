const { getDb, initSchema, closeDb } = require('../src/db');
const {
  runAllIngestions,
  ingestRxNorm,
  ingestOrangeBook,
  ingestPurpleBook,
  ingestOpenFdaNdc,
  ingestCmsNadac,
  ingestFdaShortages
} = require('../src/ingestion');

async function main() {
  const args = process.argv.slice(2);
  const feedArg = args.find(a => a.startsWith('--feed='));
  const feed = feedArg ? feedArg.split('=')[1].toLowerCase() : 'all';

  const db = getDb();
  initSchema(db);

  console.log(`Running ingestion for feed: ${feed}...`);

  try {
    switch (feed) {
      case 'rxnorm':
        console.log('Ingesting NLM RxNorm concepts...');
        const rx = await ingestRxNorm(db);
        console.log(`  RxNorm: ${rx.inserted} records`);
        break;
      case 'orange_book':
        console.log('Ingesting FDA Orange Book...');
        const ob = await ingestOrangeBook(db);
        console.log(`  Orange Book: ${ob.inserted} records`);
        break;
      case 'purple_book':
        console.log('Ingesting FDA Purple Book...');
        const pb = await ingestPurpleBook(db);
        console.log(`  Purple Book: ${pb.inserted} records`);
        break;
      case 'openfda_ndc':
        console.log('Ingesting OpenFDA NDC Directory...');
        const ndc = await ingestOpenFdaNdc(db);
        console.log(`  OpenFDA NDC: ${ndc.inserted} records`);
        break;
      case 'cms_nadac':
        console.log('Ingesting CMS NADAC pricing...');
        const nadac = await ingestCmsNadac(db);
        console.log(`  CMS NADAC: ${nadac.inserted} records`);
        break;
      case 'fda_shortages':
        console.log('Ingesting FDA Drug Shortages...');
        const shortages = await ingestFdaShortages(db);
        console.log(`  FDA Shortages: ${shortages.inserted} records`);
        break;
      case 'all':
      default:
        console.log('Ingesting all 6 official feeds in relational order...');
        const all = await runAllIngestions(db);
        console.log('Ingestion completed successfully:');
        console.log(`  - RxNorm Concepts: ${all.rxnorm.inserted}`);
        console.log(`  - FDA Orange Book ANDA Approvals: ${all.orange_book.inserted}`);
        console.log(`  - FDA Purple Book Biosimilars: ${all.purple_book.inserted}`);
        console.log(`  - OpenFDA NDC Commercial Listings: ${all.openfda_ndc.inserted}`);
        console.log(`  - CMS NADAC Pricing Records: ${all.cms_nadac.inserted}`);
        console.log(`  - FDA Drug Shortages: ${all.fda_shortages.inserted}`);
        break;
    }
  } catch (err) {
    console.error('Ingestion failed:', err);
    process.exitCode = 1;
  } finally {
    closeDb();
  }
}

main();
