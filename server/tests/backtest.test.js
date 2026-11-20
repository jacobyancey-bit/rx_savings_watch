const test = require('node:test');
const assert = require('node:assert/strict');
const { runBacktest } = require('../scripts/backtest');

test('Backtest: historical time-travel backtest suite passes all criteria', async () => {
  const report = await runBacktest({ silent: true });

  // 1. 100% Recall (all actual commercial launches detected)
  assert.equal(report.recall, 1.0, 'Recall must be 100%');
  assert.equal(report.false_negatives, 0, 'Zero false negatives on historical launches');

  // 2. Zero false positives on brand-only drugs
  assert.equal(report.false_positives, 0, 'Must have zero false positives on brand-only drugs');
  assert.equal(report.precision, 1.0, 'Precision must be 100%');

  // 3. True negatives
  assert.ok(report.true_negatives >= 2, 'Brand-only drugs (Eliquis, Jardiance) properly recognized');

  // 4. Exact launch lag times verified
  const vyvanse = report.details.find(d => d.id === 'scenario_vyvanse');
  assert.ok(vyvanse.passed);
  assert.equal(vyvanse.lag_days, 5, 'Vyvanse lag time must be exactly 5 days');

  const humira = report.details.find(d => d.id === 'scenario_humira');
  assert.ok(humira.passed);
  assert.equal(humira.lag_days, 2321, 'Humira biosimilar lag time must be exactly 2321 days');

  const truvada = report.details.find(d => d.id === 'scenario_truvada');
  assert.ok(truvada.passed);
  assert.equal(truvada.lag_days, 1212, 'Truvada lag time must be exactly 1212 days');

  assert.equal(report.all_passed, true, 'All historical scenarios must pass');
});
