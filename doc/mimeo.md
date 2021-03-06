Mimeo
=====

About
----

Mimeo is a specialized replication extension for copying specific tables in one of several specialized ways from any number of source databases to a destination database where mimeo is installed. 

Snapshot replication is for copying the entire table from the source to the destination every time it is run. This is the only one of the replication types that can automatically replicate column changes (add, drop, rename, new type). If you're taking advantage of this please use the post_script column in the refresh_config_snap table to reproduce permissions or constraints after the destination is recreated. Indexes will be automatically recreated if the p_index parameter for the refresh_snap() function is set to true.

Incremental replication comes in two forms: Insert Only and Insert/Update Only. This can only be done on a table that has a timestamp control column that is set during every insert and/or update. The update replication requires that the source has a primary key. Insert-only replication doesn't require a primary key, just the control column. If the source table ever has rows deleted, this WILL NOT be replicated to the destination.  
Since incremental replication is time-based, systems that do not run in UTC time can have issues during DST changes. To account for this, these maker functions check the timezone of the server and if it is anything but UTC/GMT, it sets dst_active to true in the config table. This causes all replication to pause between 12:30am and 2:30am on the morning of any DST change day. These times can be adjusted if needed using the dst_start and dst_end columns in the refresh_config_inserter or refresh_config_updater table accordingly.
Also be aware that if you stop incremental replication permanently on a table, all of the source data may not have reached the destination due to the boundary settings and/or other methods that are used to keep incremental replication in a consistent state. Please double-check that all your source data is on the destination before destroying the source.

DML replication replays on the destination every insert, update and delete that happens on the source table. The special "logdel" dml replication does not remove rows that are deleted on the source. Instead it grabs the latest data that was deleted from the source, updates that on the destination and logs a timestamp of when it was deleted from the source (special destination timestamp field is called *mimeo_source_deleted* to try and keep it from conflicting with any existing column names).

The **p_condition** option in the maker functions (and the **condition** column in the config tables) can be used to as a way to designate specific rows that should be replicated. This is done using the WHERE condition part of what would be a select query on the source table. You can also designate a comma separated list of tables before the WHERE keyword if you need to join against other tables on the SOURCE database. When doing this, assume that the source table is already listed as part of the FROM clause and that your table will be second in the list (which means you must begin with a comma). Please note that using the JOIN keyword to join again other tables is not guarenteed to work at this time. Some examples of how this field are used in the maker functions:

    SELECT mimeo.snapshot_maker(..., p_condition := 'WHERE col1 > 4 AND col2 <> ''test''');
    SELECT mimeo.dml_maker (..., p_condition := ', table2, table3 WHERE source_table.col1 = table2.col1 AND table1.col3 = table3.col3');

Mimeo uses the **pg_jobmon** extension to provide an audit trail and monitoring capability. If you're having any problems with mimeo working, check the job logs that pg_jobmon creates. https://github.com/omniti-labs/pg_jobmon

All refresh functions use the advisory lock system to ensure that jobs do not run concurrently. If a job is found to already be running, it will cleanly exit immediately and record that another job was already running in pg_jobmon. It will also log a level 2 (WARNING) status for the job so you can monitor for a refresh job running concurrently too many times which may be an indication that replication is falling behind.

The p_debug argument for any function that has it will output more verbose feedback to show what that job is doing. Most of this is also logged with pg_jobmon, but this is a quick way to see detailed info immediately.


Setup
-----

The **dblink_mapping** table contains the configuration information for the source database (where data is copied FROM). You can define as many data sources as you wish. The data source for a replicated table is declared just once in the refresh_config table mentioned below.

    insert into mimeo.dblink_mapping (data_source, username, pwd) 
    values ('host=pghost.com port=5432 dbname=pgdb', 'refresh', 'password');

The **data_source** value is the connection format required by dblink.
**username** and **pwd** are the credentials for connecting to the source database. Password is optional if you have security set up to not require it (just leave it NULL).

For all forms of replication, the role on the source database(s) should have at minimum select access on all tables/views to be replicated. Except for dml/logdel replication, no other setup on the source is needed for mimeo to do everything it needs.  
For dml and logdel replication some additional setup is required. The source database needs a schema created with the EXACT same name as the schema where mimeo was installed on the destination. The source role should have ownership of this schema to easily allow it to do what it needs. The source role will also need TRIGGER permissions on any source tables that it will be replicating.
    
    CREATE schema <mimeo_schema>;
    ALTER SCHEMA <mimeo_schema> OWNER TO <mimeo_role>;
    GRANT TRIGGER ON <source_table> TO <mimeo_role>;


Functions
---------

*refresh_snap(p_destination text, p_index boolean DEFAULT true, p_debug boolean DEFAULT false, p_pulldata boolean DEFAULT true)*  
 * Full table replication to the destination table given by p_destination. Automatically creates destination view and tables needed if they do not already exist.  
 * Can be setup with snapshot_maker(...) and removed with snapshot_destroyer(...) functions.  
  * p_index, an optional argument, sets whether to recreate all indexes if any of the columns on the source table change. Defaults to true. Note this only applies when the columns on the source change, not the indexes.
 * The final parameter, p_pulldata, does not generally need to be used and in most cases can just be ignored. It is primarily for internal use by the maker functions to allow their p_pulldata parameters to work.

*refresh_inserter(p_destination text, p_limit integer DEFAULT NULL, p_repull boolean DEFAULT false, p_repull_start text DEFAULT NULL, p_repull_end text DEFAULT NULL, p_debug boolean DEFAULT false)*  
 * Replication for tables that have INSERT ONLY data and contain a timestamp column that is incremented with every INSERT.
 * Can be setup with inserter_maker(...) and removed with inserter_destroyer(...) functions.  
 * p_limit, an optional argument, can be used to change the limit on how many rows are grabbed from the source with each run of the function. Defaults to all new rows if not given here or set in configuration table. Note that this makes the refresh function slightly more expensive to run as extra checks must be run to ensure data consistency.
 * p_repull, an optional argument, sets a flag to repull data from the source instead of getting new data. If this flag is set without setting the start/end arguments as well, then **ALL local data will be truncated** and the ENTIRE source table will be repulled.
 * p_repull_start and p_repull_end, optional arguments, can set a specific time period to repull source data. This is an EXCLUSIVE time period (< start, > end). If p_repull is not set, then these arguments are ignored.
    
*refresh_updater(p_destination text, p_limit integer DEFAULT NULL, p_repull boolean DEFAULT false, p_repull_start text DEFAULT NULL, p_repull_end text DEFAULT NULL, p_debug boolean DEFAULT false)*  
 * Replication for tables that have INSERT AND/OR UPDATE ONLY data and contain a timestamp column that is incremented with every INSERT AND UPDATE
 * Can be setup with updater_maker(...) and removed with updater_destroyer(...) functions.  
 * p_limit, an optional argument, can be used to change the limit on how many rows are grabbed from the source with each run of the function. Defaults to all new rows if not given here or set in configuration table. Note that this makes the refresh function slightly more expensive to run as extra checks must be run to ensure data consistency.
 * p_repull, an optional argument, sets a flag to repull data from the source instead of getting new data. If this flag is set without setting the start/end arguments as well, then **ALL local data will be truncated** and the ENTIRE source table will be repulled.
 * p_repull_start and p_repull_end, optional arguments, can set a specific time period to repull source data. This is an EXCLUSIVE time period (< start, > end). If p_repull is not set, then these arguments are ignored.

*refresh_dml(p_destination text, p_limit int default NULL, p_repull boolean DEFAULT false, p_debug boolean DEFAULT false)*  
 * Replicate tables by replaying INSERTS, UPDATES and DELETES in the order they occur on the source table. Useful for tables that are too large for snapshots.  
 * Can be setup with dml_maker(...) and removed with dml_destroyer(...) functions.  
 * p_limit, an optional argument, can be used to change the limit on how many rows are grabbed from the source with each run of the function. Defaults to all new rows if not given here or set in configuration table. Has no affect on function performance as it does with inserter/updater.
 * p_repull, an optional argument, sets a flag to repull data from the source instead of getting new data. Note that **ALL local data will be truncated** and the ENTIRE source table will be repulled.

*refresh_logdel(p_destination text, p_limit int default NULL, p_debug boolean DEFAULT false)*  
 * Replicate tables by replaying INSERTS, UPDATES and DELETES in the order they occur on the source table, but DO NOT remove deleted tables from the destination table.
 * Can be setup with logdel_maker(...) and removed with logdel_destroyer(...) functions.  
 * p_limit, an optional argument, can be used to change the limit on how many rows are grabbed from the source with each run of the function. Defaults to all new rows if not given here or set in configuration table. Has no affect on function performance as it does with inserter/updater.

*snapshot_maker(p_src_table text, p_dblink_id int, p_dest_table text DEFAULT NULL, p_index boolean DEFAULT true, p_filter text[] DEFAULT NULL, p_condition text DEFAULT NULL, p_pulldata boolean DEFAULT true)*  
 * Function to automatically setup snapshot replication for a table. By default source and destination table will have same schema and table names.  
 * Destination table CANNOT exist first due to the way the snapshot system works (view /w two tables).
 * p_dblink_id is the data_source_id from the dblink_mapping table for where the source table is located.
 * p_dest_table, an optional argument,  is to set a custom destination table. Be sure to schema qualify it if needed.
 * p_index, an optional argument, sets whether to recreate all indexes that exist on the source table on the destination. Defaults to true. Note this is only applies during replication setup. Future index changes on the source will not be propagated.
 * p_filter, an optional argument, is an array list that can be used to designate only specific columns that should be used for replication.
 * p_condition, an optional argument, is used to set criteria for specific rows that should be replicated. See additional notes in **About** section above.
 * p_pulldata, an optional argument, allows you to control if data is pulled as part of the setup. Set to 'false' to configure replication with no initial data.

*snapshot_destroyer(p_dest_table text, p_archive_option text)*  
 * Function to automatically remove a snapshot replication table from the destination.  
 * Pass 'ARCHIVE' as p_archive_option to keep a permanent copy of the snapshot table on the destination. Turns what was the view into a real table. 
  * Most recent snap is just renamed to the old view name, so all permissions, indexes, constraints, etc should be kept.  
  * Pass any other value to completely remove everything.

*inserter_maker(p_src_table text, p_control_field text, p_dblink_id int, p_boundary interval DEFAULT '00:10:00', p_dest_table text DEFAULT NULL, p_index boolean DEFAULT true, p_filter text[] DEFAULT NULL, p_condition text DEFAULT NULL, p_pulldata boolean DEFAULT true)*  
 * Function to automatically setup inserter replication for a table. By default source and destination table will have same schema and table names.  
 * If destination table already exists, no data will be pulled from the source. You can use the refresh_inserter() 'repull' option to truncate the destination table and grab all the source data. Or you can set the config table's 'last_value' column for your specified table to designate when it should start. Otherwise last_value will default to the destination's max value for the control field or, if null, the time that the maker function was run.
 * p_control_field is the column which is used as the control field (a timestamp field that is new for every insert).  
 * p_dblink_id is the data_source_id from the dblink_mapping table for where the source table is located.  
 * p_boundary, an optional argument, is a boundary value to prevent records being missed at the upper boundary of the batch. Set this to a value that will ensure all inserts will have finished for that time period when the replication runs. Default is 10 minutes which means the destination may always be 10 minutes behind the source but that also means that all inserts on the source will have finished by the time 10 minutes has passed.  
 * p_dest_table, an optional argument,  is to set a custom destination table. Be sure to schema qualify it if needed.
 * p_index, an optional argument, sets whether to recreate all indexes that exist on the source table on the destination. Defaults to true. Note this is only applies during replication setup. Future index changes on the source will not be propagated.
 * p_filter, an optional argument, is an array list that can be used to designate only specific columns that should be used for replication.
 * p_condition, an optional argument, is used to set criteria for specific rows that should be replicated. See additional notes in **About** section above.
 * p_pulldata, an optional argument, allows you to control if data is pulled as part of the setup. Set to 'false' to configure replication with no initial data.
    
*inserter_destroyer(p_dest_table text, p_archive_option text)*  
 * Function to automatically remove an inserter replication table from the destination.  
 * Pass 'ARCHIVE' as p_archive_option to leave the destination table intact. Pass any other value to completely remove everything.

*updater_maker(p_src_table text, p_control_field text, p_dblink_id int, p_boundary interval DEFAULT '00:10:00', p_dest_table text DEFAULT NULL, p_index boolean DEFAULT true, p_filter text[] DEFAULT NULL, p_condition text DEFAULT NULL, p_pulldata boolean DEFAULT true, p_pk_name text[] DEFAULT NULL, p_pk_type text[] DEFAULT NULL)*  
 * Function to automatically setup updater replication for a table. By default source and destination table will have same schema and table names.  
 * Source table must have a primary key or unique index. Either the primary key or a unique index (first in alphabetical order if more than one) on the source table will be obtained automatically. Columns of primary/unique key cannot be arrays nor can they be an expression.  
 * If destination table already exists, no data will be pulled from the source. You can use the refresh_updater() 'repull' option to truncate the destination table and grab all the source data. Or you can set the config table's 'last_value' column for your specified table to designate when it should start. Otherwise last_value will default to the destination's max value for the control field or, if null, the time that the maker function was run.
 * p_control_field is the column which is used as the control field (a timestamp field that is new for every insert AND update).  
 * p_dblink_id is the data_source_id from the dblink_mapping table for where the source table is located.  
 * p_boundary, an optional argument, is a boundary value to prevent records being missed at the upper boundary of the batch. Set this to a value that will ensure all inserts/updates will have finished for that time period when the replication runs. Default is 10 minutes which means the destination may always be 10 minutes behind the source but that also means that all inserts/updates on the source will have finished by the time 10 minutes has passed.  
 * p_dest_table, an optional argument,  is to set a custom destination table. Be sure to schema qualify it if needed.
 * p_index, an optional argument, sets whether to recreate all indexes that exist on the source table on the destination. Defaults to true. Note this is only applies during replication setup. Future index changes on the source will not be propagated.
 * p_filter, an optional argument, is an array list that can be used to designate only specific columns that should be used for replication.
 * p_condition, an optional argument, is used to set criteria for specific rows that should be replicated. See additional notes in **About** section above.
 * p_pulldata, an optional argument, allows you to control if data is pulled as part of the setup. Set to 'false' to configure replication with no initial data.
 * p_pk_name, an optional argument, is an array of the columns that make up the primary/unique key on the source table. This overrides the automatic retrieval from the source.
 * p_pk_type, an optional argument, is an array of the column types that make up the primary/unique key on the source table. This overrides the automatic retrieval from the source. Ensure the types are in the same order as p_pk_name.

*updater_destroyer(p_dest_table text, p_archive_option text)*  
 * Function to automatically remove an updater replication table from the destination.  
 * Pass 'ARCHIVE' as p_archive_option to leave the destination table intact. Pass any other value to completely remove everything.

*dml_maker(p_src_table text, p_dblink_id int, p_dest_table text DEFAULT NULL, p_index boolean DEFAULT true, p_filter text[] DEFAULT NULL, p_condition text DEFAULT NULL, p_pulldata boolean DEFAULT true, p_pk_name text[] DEFAULT NULL, p_pk_type text[] DEFAULT NULL)*  
 * Function to automatically setup dml replication for a table. See setup instructions above for permissions that are needed on source database. By default source and destination table will have same schema and table names.  
 * Source table must have a primary key or unique index. Either the primary key or a unique index (first in alphabetical order if more than one) on the source table will be obtained automatically. Columns of primary/unique key cannot be arrays nor can they be an expression.  
 * If destination table already exists, no data will be pulled from the source. You can use the refresh_dml() 'repull' option to truncate the destination table and grab all the source data.  
 * The queue table and trigger function on the source database will have permissions set to allow any current roles with write privileges on the source table to use them. If any further privileges are changed on the source table, the queue and trigger function will have to have their privileges adjusted manually.
 * p_dblink_id is the data_source_id from the dblink_mapping table for where the source table is located.  
 * p_dest_table, an optional argument,  is to set a custom destination table. Be sure to schema qualify it if needed.
 * p_index, an optional argument, sets whether to recreate all indexes that exist on the source table on the destination. Defaults to true. Note this is only applies during replication setup. Future index changes on the source will not be propagated.
 * p_filter, an optional argument, is an array list that can be used to designate only specific columns that should be used for replication.
  * Source table trigger will only fire on UPDATES of the given columns (uses UPDATE OF col1 [, col2...]).
 * p_condition, an optional argument, is used to set criteria for specific rows that should be replicated. See additional notes in **About** section above.
 * p_pulldata, an optional argument, allows you to control if data is pulled as part of the setup. Set to 'false' to configure replication with no initial data.
 * p_pk_name, an optional argument, is an array of the columns that make up the primary/unique key on the source table. This overrides the automatic retrieval from the source.
 * p_pk_type, an optional argument, is an array of the column types that make up the primary/unique key on the source table. This overrides the automatic retrieval from the source. Ensure the types are in the same order as p_pk_name.

*dml_destroyer(p_dest_table text, p_archive_option text)*  
 * Function to automatically remove a dml replication table from the destination. This will also automatically remove the associated objects from the source database if the dml_maker() function was used to create it.  
 * Be aware that only the owner of a table can drop triggers, so this function will fail if the source database mimeo role does not own the source table. This is the way PostgreSQL permissions are currently setup and there's nothing I can do about it.
 * Pass 'ARCHIVE' as p_archive_option to leave the destination table intact. Pass any other value to completely remove everything.

*logdel_maker(p_src_table text, p_dblink_id int, p_dest_table text DEFAULT NULL, p_index boolean DEFAULT true, p_filter text[] DEFAULT NULL, p_condition text DEFAULT NULL, p_pulldata boolean DEFAULT true, p_pk_name text[] DEFAULT NULL, p_pk_type text[] DEFAULT NULL)*  
 * Function to automatically setup logdel replication for a table. See setup instructions above for permissions that are needed on source database. By default source and destination table will have same schema and table names.  
 * Source table must have a primary key or unique index. Either the primary key or a unique index (first in alphabetical order if more than one) on the source table will be obtained automatically. Columns of primary/unique key cannot be arrays nor can they be an expression.  
 * If destination table already exists, no data will be pulled from the source. You can use the refresh_logdel() 'repull' option to truncate the destination table and grab all the source data.
 * The queue table and trigger function on the source database will have permissions set to allow any current roles with write privileges on the source table to use them. If any further privileges are changed on the source table, the queue and trigger function will have to have their privileges adjusted manually.
 * p_dblink_id is the data_source_id from the dblink_mapping table for where the source table is located.  
 * p_dest_table, an optional argument,  is to set a custom destination table. Be sure to schema qualify it if needed.
 * p_index, an optional argument, sets whether to recreate all indexes that exist on the source table on the destination. Defaults to true. Note this is only applies during replication setup. Future index changes on the source will not be propagated.
 * p_pulldata, an optional argument, allows you to control if data is pulled as part of the setup. Set to 'false' to configure replication with no initial data.
 * p_filter, an optional argument, is an array list that can be used to designate only specific columns that should be used for replication.
  * Source table trigger will only fire on UPDATES of the given columns (uses UPDATE OF col1 [, col2...]).
 * p_condition, an optional argument, is used to set criteria for specific rows that should be replicated. See additional notes in **About** section above.
 * p_pk_name, an optional argument, is an array of the columns that make up the primary/unique key on the source table. This overrides the automatic retrieval from the source.
 * p_pk_type, an optional argument, is an array of the column types that make up the primary/unique key on the source table. This overrides the automatic retrieval from the source. Ensure the types are in the same order as p_pk_name.

*logdel_destroyer(p_dest_table text, p_archive_option text)*  
 * Function to automatically remove a logdel replication table from the destination. This will also automatically remove the associated objects from the source database if the dml_maker() function was used to create it.  
 * Be aware that only the owner of a table can drop triggers, so this function will fail if the source database mimeo role does not own the source table. This is the way PostgreSQL permissions are currently setup and there's nothing I can do about it.
 * Pass 'ARCHIVE' as p_archive_option to leave the destination table intact. Pass any other value to completely remove everything.


!!!!!!!!!!!!!!!!!  THIS FUNCTION IS DEPRECATED AND WILL BE EXPLICITLY DROPPED IN VERSION 1.0 !!!!!!!!!!!!!!!!!  
*run_refresh(p_type text, p_batch int DEFAULT 4, p_debug boolean DEFAULT false)*  
 * This function will run the refresh function for all tables the tables listed in refresh_config for the type given by p_type. Note that the jobs within a batch are run sequentially, not concurrently (working to try and see if I can get it working concurrently).  
 * p_batch sets how many of each type of refresh job will be kicked off each time run_refresh is called.

This function is no longer installed as of 0.10.0, but may still be around if you started using it before then. It was not dropped from the database in the 0.10.0 update to avoid breaking scheduled replication, but it will be explicitly droped when version 1.0 is released.

Using this function, a single failure of a replication job when running batches greater than one would cause ALL replication jobs that ran before it in the same batch to roll back. This could continue without knowing that the other jobs were never running successfully on time since pg_jobmon's log entries are not rolled back and the jobs were assumed to have completed successfully.

Please use the external python script of the same name instead for more reliable batch runs (see **Extras** below). With that script each job is commited individually.

!!!!!!!!!!!!!!!!!  THIS FUNCTION IS DEPRECATED AND WILL BE EXPLICITLY DROPPED IN VERSION 1.0 !!!!!!!!!!!!!!!!!  

Tables
------

*dblink_mapping*  
    Stores all source database connection data

    data_source_id  - automatically assigned ID number for the source database connection
    data_source     - dblink string for source database connection
    username        - role that mimeo uses to connect to the source database
    pwd             - password for above role
    dbh_attr        - currently unused. If someone finds they need special connection attributes let me know and I'll work on incorporating this sooner.

*refresh_config*  
    Parent table for all config types. All child config tables below contain these columns. No data is actually stored in this table

    dest_table      - Tablename on destination database. If not public, should be schema qualified
    type            - Type of replication. Enum of one of the following values: snap, inserter, updater, dml, logdel
    dblink          - Foreign key on the data_source_id column from dblink_mapping table
    last_run        - Timestamp of the last run of the job. Used by run_refresh() to know when to do the next run of a job.
    filter          - Array containing specific column names that should be used in replication.
    condition       - Used to set criteria for specific rows that should be replicated. See additional notes in **About** section above.
    period          - Interval used for the run_refresh() function to indicate how often this refresh job should be run at a minimum
    batch_limit     - Limit the number of rows to be processed for each run of the refresh job. If left NULL (the default), all new rows are fetched every refresh.

*refresh_config_snap*  
    Child of refresh_config. Contains config info for snapshot replication jobs.

    source_table    - Table name from source database. If not public, should be schema qualified
    post_script     - Text array of commands to run should the source columns ever change. Each value in the array is run as a single command
                      Should contain commands for things such as recreating indexes/constraints or granting permission

*refresh_config_inserter*  
    Child of refresh_config. Contains config info for inserter replication jobs.

    source_table    - Table name from source database. If not public, should be schema qualified
    control         - Column name that contains the timestamp that is updated on every insert
    boundary        - Interval to adjust upper boundary max value of control field. Default is 10 minutes. See inserter_maker() for more info.
    last_value      - This is the max value of the control field from the last run and controls the time period of the batch of data pulled from the source table. 
    dst_active      - Boolean set to true of database is not running on a server in UTC/GMT time. See About for more info
    dst_start       - Integer representation of the time that DST starts. Ex: 00:30 would be 30
    dst_end         - Integer representation of the time that DST ends. Ex: 02:30 would be 230

*refresh_config_updater*  
    Child of refresh_config. Contains config info for updater replication jobs.

    source_table    - Table name from source database. If not public, should be schema qualified
    control         - Column name that contains the timestamp that is updated on every insert AND update
    boundary        - Interval to adjust upper boundary max value of control field. Default is 10 minutes. See updater_maker() for more info.
    last_value      - This is the max value of the control field from the last run and controls the time period of the batch of data pulled from the source table. 
    pk_name         - Text array of all the column names that make up the source table primary key
    pk_type         - Text array of all the column types that make up the source table primary key
    dst_active      - Boolean set to true of database is not running on a server in UTC/GMT time. See About for more info
    dst_start       - Integer representation of the time that DST starts. Ex: 00:30 would be 30
    dst_end         - Integer representation of the time that DST ends. Ex: 02:30 would be 230

*refresh_config_dml*  
    Child of refresh_config. Contains config info for dml replication jobs.

    source_table    - Table name from source database. If not public, should be schema qualified
    control         - Schema qualified name of the queue table on the source database for this table
    pk_name         - Text array of all the column names that make up the source table primary key
    pk_type         - Text array of all the column types that make up the source table primary key
 
*refresh_config_logdel*  
    Child of refresh_config. Contains config info for logdel replication jobs.

    source_table    - Table name from source database. If not public, should be schema qualified
    control         - Schema qualified name of the queue table on the source database for this table
    pk_name         - Text array of all the column names that make up the source table primary key
    pk_type         - Text array of all the column types that make up the source table primary key

Extras
------

*run_refresh.py*
 * A python script to automatically run replication for tables that have their ''period'' set in the config table.
 * This script can be run as often as needed and refreshes will only fire if their interval period has passed.
 * --connection (-c)  Option to set the psycopg connection string to the database. Default is "host=localhost".
 * --schema (-s)  Option to set the schema that mimeo is installed to. Defaults to "mimeo".
 * --type (-t)  Option to set which type of replication to run (snap, inserter, updater, dml, logdel). Default is all types.
 * --batch_limit (-b)  Option to set how many tables to replicate in a single run of the script. Default is all jobs scheduled to run at time script is run.
 * Please see the howto.md file for some examples.

*refresh_snap_pre90.sql*
 * Alternate function for refresh_snap to provide a way to use a pre-9.0 version of PostgreSQL as the source database.
 * Useful if you're using mimeo to upgrade PostgreSQL across major versions.
 * Please read the notes in the top of this sql file for more important information.

*dml_maker_pre90.sql*
 * Alternate function for dml_maker() to provide a way to use a pre-9.0 version of PostgreSQL as the source database.
 * Also requires "refresh_snap_pre90" to be installed as "refresh_snap".
 * Useful if you're using mimeo to upgrade PostgreSQL across major versions.
 * Please read the notes in the top of this sql file for more important information.

*refresh_dml_pre91.sql*
 * Alternate function for refresh_dml() to provide a way to use a pre-9.1 version of PostgreSQL as the source.
 * Useful if you're using mimeo to upgrade PostgreSQL across major versions. 
 * Please read the notes in the top of this sql file for more important information.
