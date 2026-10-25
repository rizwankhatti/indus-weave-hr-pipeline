USE IndusWeave;
GO

IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'quality')
BEGIN
    EXEC('CREATE SCHEMA quality');
END
GO

DROP TABLE IF EXISTS quality.dq_results;

CREATE TABLE quality.dq_results (
    check_id INT IDENTITY(1,1) PRIMARY KEY,
    check_name VARCHAR(150) NOT NULL,
    check_category VARCHAR(50) NOT NULL, -- Uniqueness, Referential, Reconciliation, Domain, Business Sanity
    table_name VARCHAR(100) NOT NULL,
    status VARCHAR(20) NOT NULL,        -- 'PASS' or 'FAIL'
    records_failed INT DEFAULT 0,
    error_message VARCHAR(500) NULL,
    executed_at DATETIME2 DEFAULT SYSDATETIME()
);
GO


`
