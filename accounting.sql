DROP SCHEMA IF EXISTS accounting CASCADE;
CREATE SCHEMA accounting;

DROP TABLE IF EXISTS accounting.account;
CREATE TABLE accounting.account (
    id INTEGER GENERATED ALWAYS AS IDENTITY,
    accounttype TEXT,
    code TEXT,
    PRIMARY KEY (id)
);


CREATE OR REPLACE FUNCTION accounting.posting_balances(arg_posting_base_id INTEGER)
    RETURNS BOOLEAN AS $_$
DECLARE
    debit_sum MONEY;
    credit_sum MONEY;
BEGIN
    SELECT SUM(debit_amount) INTO debit_sum FROM accounting.posting_debit WHERE posting_base_id = arg_posting_base_id;
    SELECT SUM(credit_amount) INTO credit_sum FROM accounting.posting_credit WHERE posting_base_id = arg_posting_base_id;
    RETURN (debit_sum = credit_sum);
END;
$_$ LANGUAGE plpgsql;


DROP TABLE IF EXISTS accounting.posting_base;
CREATE TABLE accounting.posting_base (
    id INTEGER GENERATED ALWAYS AS IDENTITY,
    occurred DATE NOT NULL,
    complete BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (id),
    UNIQUE(id, occurred, complete),
    CHECK ((complete IS TRUE AND accounting.posting_balances(id)) OR NOT complete)
);

DROP SEQUENCE IF EXISTS posting_id_seq CASCADE;
CREATE SEQUENCE IF NOT EXISTS posting_id_seq START 1;


DROP TABLE IF EXISTS accounting.posting_debit;
CREATE TABLE accounting.posting_debit (
    id INTEGER NOT NULL DEFAULT nextval('posting_id_seq'),
    posting_base_id INTEGER NOT NULL,
    debit_amount MONEY NOT NULL,
    debit_accountid INTEGER NOT NULL,
    PRIMARY KEY (posting_base_id),
    FOREIGN KEY (posting_base_id) REFERENCES accounting.posting_base (id) ON DELETE CASCADE,
    FOREIGN KEY (debit_accountid) REFERENCES accounting.account (id) ON DELETE CASCADE,
    UNIQUE(id),
    UNIQUE(id, debit_accountid),
    CHECK (debit_amount > '0'::MONEY)
);

DROP TABLE IF EXISTS accounting.posting_credit;
CREATE TABLE accounting.posting_credit (
    id INTEGER NOT NULL DEFAULT nextval('posting_id_seq'),
    posting_base_id INTEGER NOT NULL,
    credit_amount MONEY NOT NULL,
    credit_accountid INTEGER NOT NULL,
    PRIMARY KEY (id),
    FOREIGN KEY (posting_base_id) REFERENCES accounting.posting_base (id) ON DELETE CASCADE,
    FOREIGN KEY (credit_accountid) REFERENCES accounting.account (id) ON DELETE CASCADE,
    UNIQUE(id, credit_amount, credit_accountid),
    CHECK (credit_amount > '0'::MONEY)
);
