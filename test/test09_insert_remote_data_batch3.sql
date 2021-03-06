SELECT set_config('search_path','mimeo, dblink, tap',false);

SELECT plan(2);

SELECT dblink_connect('mimeo_test', 'host=localhost port=5432 dbname=mimeo_source user=mimeo_test password=mimeo_test');
SELECT is(dblink_get_connections() @> '{mimeo_test}', 't', 'Remote database connection established');

-- Insert new data
SELECT dblink_exec('mimeo_test', 'INSERT INTO mimeo_source.snap_test_source VALUES (generate_series(20001,100000), ''test''||generate_series(20001,100000)::text)');
SELECT dblink_exec('mimeo_test', 'INSERT INTO mimeo_source.inserter_test_source VALUES (generate_series(20001,100000), ''test''||generate_series(20001,100000)::text)');
SELECT dblink_exec('mimeo_test', 'INSERT INTO mimeo_source.updater_test_source VALUES (generate_series(20001,100000), ''test''||generate_series(20001,100000)::text)');
SELECT dblink_exec('mimeo_test', 'INSERT INTO mimeo_source.dml_test_source VALUES (generate_series(20001,100000), ''test''||generate_series(20001,100000)::text)');
SELECT dblink_exec('mimeo_test', 'INSERT INTO mimeo_source.dml_test_source2 VALUES (generate_series(20001,100000), ''test''||generate_series(20001,100000)::text)');
SELECT dblink_exec('mimeo_test', 'INSERT INTO mimeo_source.dml_test_source_nodata VALUES (generate_series(20001,100000), ''test''||generate_series(20001,100000)::text)');
SELECT dblink_exec('mimeo_test', 'INSERT INTO mimeo_source.dml_test_source_filter VALUES (generate_series(20001,100000), ''test''||generate_series(20001,100000)::text)');
SELECT dblink_exec('mimeo_test', 'INSERT INTO mimeo_source.dml_test_source_condition VALUES (generate_series(20001,100000), ''test''||generate_series(20001,100000)::text)');
SELECT dblink_exec('mimeo_test', 'INSERT INTO mimeo_source.logdel_test_source VALUES (generate_series(20001,100000), ''test''||generate_series(20001,100000)::text)');
SELECT dblink_exec('mimeo_test', 'INSERT INTO mimeo_source.logdel_test_source2 VALUES (generate_series(20001,100000), ''test''||generate_series(20001,100000)::text)');
SELECT dblink_exec('mimeo_test', 'INSERT INTO mimeo_source.logdel_test_source_nodata VALUES (generate_series(20001,100000), ''test''||generate_series(20001,100000)::text)');
SELECT dblink_exec('mimeo_test', 'INSERT INTO mimeo_source.logdel_test_source_filter VALUES (generate_series(20001,100000), ''test''||generate_series(20001,100000)::text)');
SELECT dblink_exec('mimeo_test', 'INSERT INTO mimeo_source.logdel_test_source_condition VALUES (generate_series(20001,100000), ''test''||generate_series(20001,100000)::text)');

-- Data for testing updater
SELECT dblink_exec('mimeo_test', 'UPDATE mimeo_source.updater_test_source SET col2 = ''changed'', col3 = clock_timestamp() WHERE col1 between 25000 and 30000');

-- Data for testing dml
SELECT dblink_exec('mimeo_test', 'UPDATE mimeo_source.dml_test_source2 SET col2 = ''changed'' WHERE col1 between 35000 and 41000');
SELECT dblink_exec('mimeo_test', 'DELETE FROM mimeo_source.dml_test_source2 WHERE col1 between 45000 and 46000');
SELECT dblink_exec('mimeo_test', 'UPDATE mimeo_source.dml_test_source_condition SET col2 = ''changed''||col1 WHERE col1 > 95000');
SELECT dblink_exec('mimeo_test', 'DELETE FROM mimeo_source.dml_test_source_condition WHERE col1 <= 30000');

-- Data for testing logdel
SELECT dblink_exec('mimeo_test', 'UPDATE mimeo_source.logdel_test_source2 SET col2 = ''changed'' WHERE col1 between 36000 and 42000');
SELECT dblink_exec('mimeo_test', 'DELETE FROM mimeo_source.logdel_test_source2 WHERE col1 between 45500 and 45520');
SELECT dblink_exec('mimeo_test', 'UPDATE mimeo_source.logdel_test_source_condition SET col2 = ''changed''||col1 WHERE col1 > 18000');


SELECT dblink_disconnect('mimeo_test');
--SELECT is_empty('SELECT dblink_get_connections() @> ''{mimeo_test}''', 'Close remote database connection');

SELECT pass('Completed 3rd batch of data inserts/updates/deletes for remote tables. Sleeping for 10 seconds to ensure gap for incremental tests...');
SELECT pg_sleep(10);

SELECT * FROM finish();
