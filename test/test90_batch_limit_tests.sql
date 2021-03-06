-- This should be the last batch of tests since I don't feel like resetting the batch limits for any to come after them

SELECT set_config('search_path','mimeo, dblink, tap',false);

SELECT plan(14);

SELECT dblink_connect('mimeo_test', 'host=localhost port=5432 dbname=mimeo_source user=mimeo_test password=mimeo_test');
SELECT is(dblink_get_connections() @> '{mimeo_test}', 't', 'Remote database connection established');

UPDATE refresh_config_inserter SET batch_limit = 500 WHERE dest_table = 'mimeo_source.inserter_test_source';
UPDATE refresh_config_updater SET batch_limit = 500 WHERE dest_table = 'mimeo_source.updater_test_source';
UPDATE refresh_config_dml SET batch_limit = 500 WHERE dest_table = 'mimeo_source.dml_test_source';
UPDATE refresh_config_logdel SET batch_limit = 500 WHERE dest_table = 'mimeo_source.logdel_test_source';

SELECT results_eq ('SELECT batch_limit FROM refresh_config_inserter WHERE dest_table = ''mimeo_source.inserter_test_source''', ARRAY[500], 
    'Check that batch_limit got set for inserter');
SELECT results_eq ('SELECT batch_limit FROM refresh_config_updater WHERE dest_table = ''mimeo_source.updater_test_source''', ARRAY[500], 
    'Check that batch_limit got set for updater');
SELECT results_eq ('SELECT batch_limit FROM refresh_config_dml WHERE dest_table = ''mimeo_source.dml_test_source''', ARRAY[500], 
    'Check that batch_limit got set for dml');
SELECT results_eq ('SELECT batch_limit FROM refresh_config_logdel WHERE dest_table = ''mimeo_source.logdel_test_source''', ARRAY[500], 
    'Check that batch_limit got set for logdel');

SELECT dblink_exec('mimeo_test', 'INSERT INTO mimeo_source.inserter_test_source (col1, col2, col3) VALUES (generate_series(100001,110000), ''test''||generate_series(100001,110000)::text, now())');
SELECT dblink_exec('mimeo_test', 'INSERT INTO mimeo_source.updater_test_source (col1, col2, col3) VALUES (generate_series(100001,110000), ''test''||generate_series(100001,110000)::text, now())');
SELECT dblink_exec('mimeo_test', 'INSERT INTO mimeo_source.dml_test_source (col1, col2, col3) VALUES (generate_series(100001,110000), ''test''||generate_series(100001,110000)::text, now())');
SELECT dblink_exec('mimeo_test', 'INSERT INTO mimeo_source.logdel_test_source (col1, col2, col3) VALUES (generate_series(100001,110000), ''test''||generate_series(100001,110000)::text, now())');

SELECT pass('Sleeping for 10 seconds to ensure gap for incremental tests...');
SELECT pg_sleep(10);

SELECT refresh_inserter('mimeo_source.inserter_test_source');
SELECT refresh_updater('mimeo_source.updater_test_source');
SELECT refresh_dml('mimeo_source.dml_test_source');
SELECT refresh_logdel('mimeo_source.logdel_test_source');

-- #### INSERTER & UPDATER should have gotten no rows due to all column values having the same timestamp
SELECT results_eq('SELECT col1, col2, col3 FROM mimeo_source.inserter_test_source ORDER BY col1 ASC',
    'SELECT * FROM dblink(''mimeo_test'', ''SELECT col1, col2, col3 FROM mimeo_source.inserter_test_source WHERE col1 <= 100000 ORDER BY col1 ASC'') t (col1 int, col2 text, col3 timestamptz)',
    'Check data for: mimeo_source.inserter_test_source');

SELECT results_eq('SELECT col1, col2, col3 FROM mimeo_source.updater_test_source ORDER BY col1 ASC',
    'SELECT * FROM dblink(''mimeo_test'', ''SELECT col1, col2, col3 FROM mimeo_source.updater_test_source WHERE col1 <= 100000 ORDER BY col1 ASC'') t (col1 int, col2 text, col3 timestamptz)',
    'Check data for: mimeo_source.updater_test_source');

-- #### DML & LOGDEL should have worked fine and only gotten 500 rows. Should be warning in jobmon log, but don't need to test for that here
SELECT results_eq('SELECT col1, col2, col3 FROM mimeo_source.dml_test_source ORDER BY col1 ASC',
    'SELECT * FROM dblink(''mimeo_test'', ''SELECT col1, col2, col3 FROM mimeo_source.dml_test_source WHERE col1 <= 100500 ORDER BY col1 ASC'') t (col1 int, col2 text, col3 timestamptz)',
    'Check data for: mimeo_source.dml_test_source');

SELECT results_eq('SELECT col1, col2, col3 FROM mimeo_source.logdel_test_source ORDER BY col1 ASC',
    'SELECT * FROM dblink(''mimeo_test'', ''SELECT col1, col2, col3 FROM mimeo_source.logdel_test_source WHERE col1 <= 100500 ORDER BY col1 ASC'') t (col1 int, col2 text, col3 timestamptz)',
    'Check data for: mimeo_source.logdel_test_source');

SELECT refresh_inserter('mimeo_source.inserter_test_source', p_limit := 20000);
SELECT refresh_updater('mimeo_source.updater_test_source', p_limit := 20000);
SELECT refresh_dml('mimeo_source.dml_test_source', p_limit := 20000);
SELECT refresh_logdel('mimeo_source.logdel_test_source', p_limit := 20000);

-- #### Should now have all rows
SELECT results_eq('SELECT col1, col2, col3 FROM mimeo_source.inserter_test_source ORDER BY col1 ASC',
    'SELECT * FROM dblink(''mimeo_test'', ''SELECT col1, col2, col3 FROM mimeo_source.inserter_test_source ORDER BY col1 ASC'') t (col1 int, col2 text, col3 timestamptz)',
    'Check data for: mimeo_source.inserter_test_source');

SELECT results_eq('SELECT col1, col2, col3 FROM mimeo_source.updater_test_source ORDER BY col1 ASC',
    'SELECT * FROM dblink(''mimeo_test'', ''SELECT col1, col2, col3 FROM mimeo_source.updater_test_source ORDER BY col1 ASC'') t (col1 int, col2 text, col3 timestamptz)',
    'Check data for: mimeo_source.updater_test_source');

SELECT results_eq('SELECT col1, col2, col3 FROM mimeo_source.dml_test_source ORDER BY col1 ASC',
    'SELECT * FROM dblink(''mimeo_test'', ''SELECT col1, col2, col3 FROM mimeo_source.dml_test_source ORDER BY col1 ASC'') t (col1 int, col2 text, col3 timestamptz)',
    'Check data for: mimeo_source.dml_test_source');

SELECT results_eq('SELECT col1, col2, col3 FROM mimeo_source.logdel_test_source ORDER BY col1 ASC',
    'SELECT * FROM dblink(''mimeo_test'', ''SELECT col1, col2, col3 FROM mimeo_source.logdel_test_source ORDER BY col1 ASC'') t (col1 int, col2 text, col3 timestamptz)',
    'Check data for: mimeo_source.logdel_test_source');

SELECT dblink_disconnect('mimeo_test');
--SELECT is_empty('SELECT dblink_get_connections() @> ''{mimeo_test}''', 'Close remote database connection');

SELECT * FROM finish();
