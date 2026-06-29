-- ============================================================
-- PostgreSQL 数据库空间分析脚本（仅只读，不修改任何数据）
-- 目标库：hdr
-- 用途：分析 900G+ 空间构成，定位可清理的冗余
-- ============================================================

-- 1. 库级空间概览
SELECT
    pg_database.datname AS 数据库名,
    pg_size_pretty(pg_database_size(pg_database.datname)) AS 总大小,
    pg_database_size(pg_database.datname) AS 总大小_bytes
FROM pg_database
WHERE pg_database.datname = current_database();

-- 2. Schema 级空间分布
SELECT
    schemaname AS 模式名,
    pg_size_pretty(SUM(pg_total_relation_size(schemaname||'.'||tablename)::bigint)) AS 总空间,
    pg_size_pretty(SUM(pg_table_size(schemaname||'.'||tablename)::bigint)) AS 表空间,
    pg_size_pretty(SUM(pg_indexes_size(schemaname||'.'||tablename)::bigint)) AS 索引空间,
    COUNT(*) AS 表数量
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
GROUP BY schemaname
ORDER BY SUM(pg_total_relation_size(schemaname||'.'||tablename)::bigint) DESC;

-- 3. TOP 50 大表（含索引空间）
SELECT
    schemaname || '.' || tablename AS 表名,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)::bigint) AS 总空间,
    pg_size_pretty(pg_table_size(schemaname||'.'||tablename)::bigint) AS 表数据空间,
    pg_size_pretty(pg_indexes_size(schemaname||'.'||tablename)::bigint) AS 索引空间,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)::bigint)
        - pg_size_pretty(pg_table_size(schemaname||'.'||tablename)::bigint)::bigint
        - pg_size_pretty(pg_indexes_size(schemaname||'.'||tablename)::bigint)::bigint
        AS 其他(TOAST等),
    (SELECT n_live_tup FROM pg_stat_user_tables WHERE schemaname=t.schemaname AND relname=t.tablename) AS 存活行数,
    (SELECT n_dead_tup FROM pg_stat_user_tables WHERE schemaname=t.schemaname AND relname=t.tablename) AS 死行数
FROM pg_tables t
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_total_relation_size(schemaname||'.'||tablename)::bigint DESC
LIMIT 50;

-- 4. 表膨胀分析（需要 pgstattuple 扩展，如未安装则跳过）
-- CREATE EXTENSION IF NOT EXISTS pgstattuple;
-- SELECT schemaname||'.'||tablename AS 表名,
--        pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)::bigint) AS 总大小,
--        (SELECT round(100.0 * (len - tuple_len) / nullif(len, 0), 2)
--         FROM pgstattuple(schemaname||'.'||tablename)) AS 膨胀率
-- FROM pg_tables
-- WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
-- ORDER BY 膨胀率 DESC NULLS LAST;

-- 5. TOP 50 大索引
SELECT
    schemaname || '.' || indexname AS 索引名,
    schemaname || '.' || tablename AS 所属表,
    pg_size_pretty(pg_relation_size((schemaname||'.'||indexname)::regclass)::bigint) AS 索引大小,
    idx_scan AS 索引扫描次数,
    idx_tup_read AS 读取行数,
    idx_tup_fetch AS 获取行数
FROM pg_indexes i
JOIN pg_stat_user_indexes ui ON ui.indexrelname = i.indexname AND ui.schemaname = i.schemaname
WHERE i.schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_relation_size((schemaname||'.'||indexname)::regclass)::bigint DESC
LIMIT 50;

-- 6. 从未使用的索引（idx_scan = 0 或极低）
SELECT
    schemaname || '.' || indexname AS 索引名,
    schemaname || '.' || tablename AS 所属表,
    pg_size_pretty(pg_relation_size((schemaname||'.'||indexname)::regclass)::bigint) AS 索引大小,
    idx_scan AS 扫描次数
FROM pg_indexes i
JOIN pg_stat_user_indexes ui ON ui.indexrelname = i.indexname AND ui.schemaname = i.schemaname
WHERE i.schemaname NOT IN ('pg_catalog', 'information_schema')
  AND idx_scan = 0
ORDER BY pg_relation_size((schemaname||'.'||indexname)::regclass)::bigint DESC;

-- 7. 重复索引检测
SELECT
    pg_size_pretty(SUM(pg_relation_size(indexrelid)::bigint)) AS 总浪费空间,
    COUNT(*) AS 重复索引数
FROM pg_index i
JOIN pg_class c ON i.indexrelid = c.oid
WHERE EXISTS (
    SELECT 1 FROM pg_index i2
    JOIN pg_class c2 ON i2.indexrelid = c2.oid
    WHERE i2.indrelid = i.indrelid
      AND i2.indexrelid <> i.indexrelid
      AND i2.indkey = i.indkey
      AND i2.indclass = i.indclass
      AND i2.indoption = i.indoption
);

-- 8. 表的死元组比例
SELECT
    schemaname,
    relname AS 表名,
    n_live_tup AS 存活行数,
    n_dead_tup AS 死行数,
    CASE WHEN n_live_tup + n_dead_tup > 0
         THEN round(100.0 * n_dead_tup / (n_live_tup + n_dead_tup), 2)
         ELSE 0 END AS 死元组比例,
    last_autovacuum AS 最后自动清理时间,
    last_manual_vacuum AS 最后手动清理时间,
    vacuum_count AS 清理次数
FROM pg_stat_user_tables
WHERE n_dead_tup > 10000
ORDER BY n_dead_tup DESC
LIMIT 30;
