-- PostgreSQL 获取所有表的 DDL（含字段注释、主键）
-- 在 pgAdmin / DBeaver 等工具中运行，复制结果即为建表语句

SELECT
    '-- ========================================' || E'\n' ||
    '-- 表名: ' || c.relname || E'\n' ||
    '-- 注释: ' || COALESCE(pg_catalog.obj_description(c.oid, 'pg_class'), '') || E'\n' ||
    '-- ========================================' || E'\n' ||
    'CREATE TABLE IF NOT EXISTS "' || c.relname || '" (' || E'\n' ||
    string_agg(
        '    "' || a.attname || '" ' ||
        pg_catalog.format_type(a.atttypid, a.atttypmod) ||
        CASE WHEN a.attnotnull THEN ' NOT NULL' ELSE '' END ||
        CASE WHEN a.atthasdef THEN ' DEFAULT ' || pg_catalog.pg_get_expr(d.adbin, d.adrelid) ELSE '' END ||
        '  /* ' || COALESCE(col_description(c.oid, a.attnum), '') || ' */',
        ',' || E'\n'
        ORDER BY a.attnum
    ) || E'\n' ||
    CASE WHEN pk.cols IS NOT NULL THEN
        ',' || E'\n' || '    PRIMARY KEY (' || pk.cols || ')'
    ELSE '' END ||
    E'\n' || ');' || E'\n' ||
    -- 添加表注释
    CASE WHEN pg_catalog.obj_description(c.oid, 'pg_class') != '' THEN
        'COMMENT ON TABLE "' || c.relname || '" IS ''' || pg_catalog.obj_description(c.oid, 'pg_class') || ''';' || E'\n'
    ELSE '' END AS ddl
FROM
    pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_catalog.pg_attribute a ON a.attrelid = c.oid
    LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
    LEFT JOIN (
        SELECT
            conrelid,
            string_agg('"' || att.attname || '"', ', ' ORDER BY att.attnum) AS cols
        FROM
            pg_catalog.pg_constraint con
            JOIN pg_catalog.pg_attribute att ON att.attrelid = con.conrelid AND att.attnum = ANY(con.conkey)
        WHERE
            con.contype = 'p'
        GROUP BY conrelid
    ) pk ON pk.conrelid = c.oid
WHERE
    c.relkind = 'r'  -- 普通表
    AND n.nspname = 'public'  -- 只查 public schema
    AND a.attnum > 0
    AND NOT a.attisdropped
GROUP BY
    c.relname, c.oid, pk.cols
ORDER BY
    c.relname;
