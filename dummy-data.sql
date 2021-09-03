/*** * * * * * * * * * * * * * * * * * * *
 * * * * A C C O U N T I N G  D A T A * * 
 *** * * * * * * * * * * * * * * * * * ***/
SET search_path = "$user", public, accounting;


INSERT INTO account (accounttype, code) VALUES ('cash-liability', 'CASH-');
INSERT INTO account (accounttype, code) VALUES ('member-asset', 'MEMBER-ASSET-');
INSERT INTO account (accounttype, code) VALUES ('membership-revenue', 'MS-REVENUE-');
INSERT INTO account (accounttype, code) VALUES ('membership-asset', 'MEMBERSHIP-ASSET-');
UPDATE account SET code = CONCAT(code, id);


CREATE OR REPLACE FUNCTION incomplete_posting_create(
    arg_credit_accountid INTEGER,
    arg_occurred DATE,
    arg_amount MONEY,
    arg_debit_accountid INTEGER
) RETURNS INTEGER AS $_$
DECLARE
    var_posting_base_id INTEGER;
    var_posting_credit_id INTEGER;
BEGIN
    INSERT INTO accounting.posting_base(occurred, complete)
    VALUES (arg_occurred, FALSE)
    RETURNING id INTO var_posting_base_id;

    INSERT INTO accounting.posting_debit(posting_base_id, debit_accountid, debit_amount)
    VALUES (var_posting_base_id, arg_debit_accountid, arg_amount);

    INSERT INTO accounting.posting_credit(posting_base_id, credit_accountid, credit_amount)
    VALUES (var_posting_base_id, arg_credit_accountid, arg_amount)
    RETURNING id INTO var_posting_credit_id;

    RETURN var_posting_base_id;
END;
$_$ LANGUAGE PLPGSQL;


CREATE OR REPLACE FUNCTION incomplete_posting_add(
    arg_credit_accountid INTEGER,
    arg_amount MONEY,
    arg_posting_base_id INTEGER
) RETURNS INTEGER AS $_$
DECLARE
    var_posting_credit_id INTEGER;
BEGIN
    INSERT INTO accounting.posting_credit(posting_base_id, credit_accountid, credit_amount)
    VALUES (arg_posting_base_id, arg_credit_accountid, arg_amount)
    RETURNING id INTO var_posting_credit_id;

    RETURN var_posting_credit_id;
END;
$_$ LANGUAGE PLPGSQL;


CREATE OR REPLACE FUNCTION journal_charge_create(
    arg_posting_base_id INTEGER
) RETURNS SETOF INTEGER AS $_$
DECLARE
    var_journal_charge_id INTEGER;
    var_posting_rec RECORD;
BEGIN

    FOR var_posting_rec IN
        SELECT
            posting_base.id AS posting_base_id, posting_base.occurred, posting_base.complete,
            posting_debit.id AS posting_debit_id, posting_debit.accountid AS debit_accountid,
            posting_credit.id AS posting_id, posting_credit.accountid AS credit_accountid,
            posting_credit.credit_amount
        FROM accounting.posting_base
        LEFT JOIN accounting.posting_debit ON (posting_base.id = posting_debit.posting_base_id)
        LEFT JOIN accounting.posting_credit ON (posting_base.id = posting_credit.posting_base_id)
        WHERE
            posting_base.id = arg_posting_base_id
    LOOP
        INSERT INTO accounting_view.journal_charge(
            id, occurred, complete,
            debit_posting_id, debit_accountid,
            posting_id, credit_accountid, credit_amount
        )
        VALUES (
            var_posting_rec.posting_base_id, var_posting_rec.occurred, var_posting_rec.complete,
            var_posting_rec.posting_debit_id, var_posting_rec.debit_accountid,
            var_posting_rec.posting_id, var_posting_rec.credit_accountid, var_posting_rec.credit_amount
        )
        RETURNING posting_id INTO var_journal_charge_id;
        RETURN NEXT var_journal_charge_id;
    END LOOP;
    RETURN;
END;
$_$ LANGUAGE PLPGSQL;


CREATE OR REPLACE FUNCTION journal_payment_create(
    arg_posting_base_id INTEGER
) RETURNS SETOF INTEGER AS $_$
DECLARE
    var_journal_charge_id INTEGER;
    var_posting_rec RECORD;
BEGIN

    FOR var_posting_rec IN
        SELECT
            posting_base.id AS posting_base_id, posting_base.occurred, posting_base.complete,
            posting_debit.id AS posting_debit_id, posting_debit.accountid AS debit_accountid,
            posting_credit.id AS posting_id, posting_credit.accountid AS credit_accountid,
            posting_credit.credit_amount
        FROM accounting.posting_base
        LEFT JOIN accounting.posting_debit ON (posting_base.id = posting_debit.posting_base_id)
        LEFT JOIN accounting.posting_credit ON (posting_base.id = posting_credit.posting_base_id)
        WHERE
            posting_base.id = arg_posting_base_id
    LOOP
        INSERT INTO accounting_view.journal_payment(
            id, occurred, complete,
            debit_posting_id, debit_accountid,
            posting_id, credit_accountid, credit_amount
        )
        VALUES (
            var_posting_rec.posting_base_id, var_posting_rec.occurred, var_posting_rec.complete,
            var_posting_rec.posting_debit_id, var_posting_rec.debit_accountid,
            var_posting_rec.posting_id, var_posting_rec.credit_accountid, var_posting_rec.credit_amount
        )
        RETURNING posting_id INTO var_journal_charge_id;
        RETURN NEXT var_journal_charge_id;
    END LOOP;
    RETURN;
END;
$_$ LANGUAGE PLPGSQL;



/**
 * Fully Paid Charge + Payment.
 */
/* * ACCOUNTING SCHEMA * */
/* membership charge #1*/
INSERT INTO posting_base (occurred, complete)
    VALUES ('2020-12-01'::DATE, FALSE);
INSERT INTO posting_debit (posting_base_id, debit_accountid, debit_amount)
VALUES (1, 2, '100'::MONEY);
INSERT INTO posting_credit (posting_base_id, credit_accountid, credit_amount)
VALUES (1, 3, '100'::MONEY);
UPDATE posting_base SET complete = TRUE where id = 1;
/* payment for the charge #2*/
INSERT INTO posting_base (occurred, complete)
    VALUES ('2020-12-10'::DATE, FALSE);
INSERT INTO posting_debit (posting_base_id, debit_accountid, debit_amount)
VALUES (2, 1, '100'::MONEY);
INSERT INTO posting_credit (posting_base_id, credit_accountid, credit_amount)
VALUES (2, 2, '100'::MONEY);
UPDATE posting_base SET complete = TRUE where id = 2;
/* ACCOUNTING VIEW SCHEMA */
INSERT INTO accounting_view.journal_charge
    (id, occurred, complete, debit_posting_id, debit_accountid, posting_id, credit_accountid, credit_amount)
    VALUES (1, '2020-12-01'::DATE, TRUE, 1, 2, 2, 3, '100'::MONEY);
INSERT INTO accounting_view.journal_payment
    (id, occurred, complete, debit_posting_id, debit_accountid, posting_id, credit_accountid, credit_amount)
    VALUES (2, '2020-12-10'::DATE, TRUE, 3, 1, 4, 2, '100'::MONEY);
/* * INVOICE SCHEMA * */
INSERT INTO invoice.invoice (memberid) VALUES (5012);
INSERT INTO invoice.invoice_component(invoice_id, posting_id)
    VALUES (1, 2);
INSERT INTO invoice.payment (memberid) VALUES (5012);
INSERT INTO invoice.payment_component(payment_id, posting_id)
    VALUES (1, 4);
INSERT INTO invoice.invoice_payment(payment_component_id, invoice_component_id)
    VALUES (1, 1);


/**
 *  Paid Charge + 2x Payments
 */
/* * ACCOUNTING SCHEMA * */
/* membership charge #3*/
INSERT INTO posting_base (occurred, complete)
    VALUES ('2020-12-01'::DATE, FALSE);
INSERT INTO posting_debit (posting_base_id, debit_accountid, debit_amount)
VALUES (3, 2, '100'::MONEY);
INSERT INTO posting_credit (posting_base_id, credit_accountid, credit_amount)
VALUES (3, 3, '100'::MONEY);
UPDATE posting_base SET complete = TRUE where id = 3;
/* payment 1 for the charge #4*/
INSERT INTO posting_base (occurred, complete)
    VALUES ('2020-12-11'::DATE, FALSE);
INSERT INTO posting_debit (posting_base_id, debit_accountid, debit_amount)
VALUES (4, 1, '50'::MONEY);
INSERT INTO posting_credit (posting_base_id, credit_accountid, credit_amount)
VALUES (4, 2, '50'::MONEY);
UPDATE posting_base SET complete = TRUE where id = 4;
/* payment 2 for the charge #5*/
INSERT INTO posting_base (occurred, complete)
    VALUES ('2020-12-11'::DATE, FALSE);
INSERT INTO posting_debit (posting_base_id, debit_accountid, debit_amount)
VALUES (5, 1, '50'::MONEY);
INSERT INTO posting_credit (posting_base_id, credit_accountid, credit_amount)
VALUES (5, 2, '50'::MONEY);
UPDATE posting_base SET complete = TRUE where id = 5;
/* ACCOUNTING VIEW SCHEMA */
INSERT INTO accounting_view.journal_charge
    (id, occurred, complete, debit_posting_id, debit_accountid, posting_id, credit_accountid, credit_amount)
    VALUES (3, '2020-12-01'::DATE, TRUE, 5, 2, 6, 3, '100'::MONEY);
INSERT INTO accounting_view.journal_payment
    (id, occurred, complete, debit_posting_id, debit_accountid, posting_id, credit_accountid, credit_amount)
    VALUES (4, '2020-12-11'::DATE, TRUE, 7, 1, 8, 2, '50'::MONEY);
INSERT INTO accounting_view.journal_payment
    (id, occurred, complete, debit_posting_id, debit_accountid, posting_id, credit_accountid, credit_amount)
    VALUES (5, '2020-12-11'::DATE, TRUE, 9, 1, 10, 2, '50'::MONEY);
/* * INVOICE SCHEMA * */
INSERT INTO invoice.invoice (memberid) VALUES (5011);
INSERT INTO invoice.invoice_component(invoice_id, posting_id)
    VALUES (2, 6);
/* Split Payment. So it was put through the PoS but split between cash & credit */
INSERT INTO invoice.payment (memberid) VALUES (5011);
INSERT INTO invoice.payment_component(payment_id, posting_id)
    VALUES (2, 8);
INSERT INTO invoice.payment_component(payment_id, posting_id)
    VALUES (2, 10);
INSERT INTO invoice.invoice_payment(payment_component_id, invoice_component_id)
    VALUES (2, 2);
INSERT INTO invoice.invoice_payment(payment_component_id, invoice_component_id)
    VALUES (3, 2);


/**
 *  Partially Paid charge.
 */
/* * ACCOUNTING SCHEMA * */
/* membership charge #6*/
INSERT INTO posting_base (occurred, complete)
    VALUES ('2020-12-01'::DATE, FALSE);
INSERT INTO posting_debit (posting_base_id, debit_accountid, debit_amount)
VALUES (6, 2, '100'::MONEY);
INSERT INTO posting_credit (posting_base_id, credit_accountid, credit_amount)
VALUES (6, 3, '100'::MONEY);
UPDATE posting_base SET complete = TRUE where id = 6;
/* payment 1 for the charge #7*/
INSERT INTO posting_base (occurred, complete)
    VALUES ('2020-12-11'::DATE, FALSE);
INSERT INTO posting_debit (posting_base_id, debit_accountid, debit_amount)
VALUES (7, 1, '50'::MONEY);
INSERT INTO posting_credit (posting_base_id, credit_accountid, credit_amount)
VALUES (7, 2, '50'::MONEY);
UPDATE posting_base SET complete = TRUE where id = 7;
/* ACCOUNTING VIEW SCHEMA */
INSERT INTO accounting_view.journal_charge
    (id, occurred, complete, debit_posting_id, debit_accountid, posting_id, credit_accountid, credit_amount)
    VALUES (6, '2020-12-01'::DATE, TRUE, 11, 2, 12, 3, '100'::MONEY);
INSERT INTO accounting_view.journal_payment
    (id, occurred, complete, debit_posting_id, debit_accountid, posting_id, credit_accountid, credit_amount)
    VALUES (7, '2020-12-11'::DATE, TRUE, 13, 1, 14, 2, '50'::MONEY);
/* * INVOICE SCHEMA * */
INSERT INTO invoice.invoice (memberid) VALUES (5015);
INSERT INTO invoice.invoice_component(invoice_id, posting_id)
    VALUES (3, 12);
INSERT INTO invoice.payment (memberid) VALUES (5015);
INSERT INTO invoice.payment_component(payment_id, posting_id)
    VALUES (3, 14);
INSERT INTO invoice.invoice_payment(payment_component_id, invoice_component_id)
    VALUES (4, 3);


/**
 * Payment paying for 2x charges.
 */
/* membership charge 1 */
INSERT INTO posting_base (occurred, complete)
    VALUES ('2020-06-01'::DATE, FALSE);
INSERT INTO posting_debit (posting_base_id, debit_accountid, debit_amount)
VALUES (8, 2, '100'::MONEY);
INSERT INTO posting_credit (posting_base_id, credit_accountid, credit_amount)
VALUES (8, 3, '100'::MONEY);
UPDATE posting_base SET complete = TRUE where id = 8;
/* membership charge 2 */
INSERT INTO posting_base (occurred, complete)
    VALUES ('2020-07-01'::DATE, FALSE);
INSERT INTO posting_debit (posting_base_id, debit_accountid, debit_amount)
VALUES (9, 2, '100'::MONEY);
INSERT INTO posting_credit (posting_base_id, credit_accountid, credit_amount)
VALUES (9, 3, '100'::MONEY);
UPDATE posting_base SET complete = TRUE where id = 9;
/* payment for the charges */
INSERT INTO posting_base (occurred, complete)
    VALUES ('2020-12-13'::DATE, FALSE);
INSERT INTO posting_debit (posting_base_id, debit_accountid, debit_amount)
VALUES (10, 1, '200'::MONEY);
INSERT INTO posting_credit (posting_base_id, credit_accountid, credit_amount)
VALUES (10, 2, '200'::MONEY);
UPDATE posting_base SET complete = TRUE where id = 10;
/* ACCOUNTING VIEW SCHEMA */
INSERT INTO accounting_view.journal_charge
    (id, occurred, complete, debit_posting_id, debit_accountid, posting_id, credit_accountid, credit_amount)
    VALUES (8, '2020-06-01'::DATE, TRUE, 15, 2, 16, 3, '100'::MONEY);
INSERT INTO accounting_view.journal_charge
    (id, occurred, complete, debit_posting_id, debit_accountid, posting_id, credit_accountid, credit_amount)
    VALUES (9, '2020-07-01'::DATE, TRUE, 17, 2, 18, 3, '100'::MONEY);
INSERT INTO accounting_view.journal_payment
    (id, occurred, complete, debit_posting_id, debit_accountid, posting_id, credit_accountid, credit_amount)
    VALUES (10, '2020-12-13'::DATE, TRUE, 19, 1, 20, 2, '200'::MONEY);
/* * INVOICE SCHEMA * */
INSERT INTO invoice.invoice (memberid) VALUES (5035);
INSERT INTO invoice.invoice_component(invoice_id, posting_id)
    VALUES (4, 16);
INSERT INTO invoice.invoice_component(invoice_id, posting_id)
    VALUES (4, 18);
INSERT INTO invoice.payment (memberid) VALUES (5035);
INSERT INTO invoice.payment_component(payment_id, posting_id)
    VALUES (4, 20);
INSERT INTO invoice.invoice_payment(payment_component_id, invoice_component_id)
    VALUES (5, 4);
INSERT INTO invoice.invoice_payment(payment_component_id, invoice_component_id)
    VALUES (5, 5);


/**
 * Payment paying for 2x charges, in separate accounts.
 */
/* membership charge 1 */
INSERT INTO posting_base (occurred, complete)
    VALUES ('2021-01-06'::DATE, FALSE);
INSERT INTO posting_debit (posting_base_id, debit_accountid, debit_amount)
VALUES (11, 2, '100'::MONEY);
INSERT INTO posting_credit (posting_base_id, credit_accountid, credit_amount)
VALUES (11, 3, '100'::MONEY);
UPDATE posting_base SET complete = TRUE where id = 11;
/* membership charge 2 */
INSERT INTO posting_base (occurred, complete)
    VALUES ('2021-01-07'::DATE, FALSE);
INSERT INTO posting_debit (posting_base_id, debit_accountid, debit_amount)
VALUES (12, 4, '100'::MONEY);
INSERT INTO posting_credit (posting_base_id, credit_accountid, credit_amount)
VALUES (12, 3, '100'::MONEY);
UPDATE posting_base SET complete = TRUE where id = 12;
/* payment for the charges */
INSERT INTO posting_base (occurred, complete)
    VALUES ('2021-01-13'::DATE, FALSE);
INSERT INTO posting_debit (posting_base_id, debit_accountid, debit_amount)
VALUES (13, 1, '200'::MONEY);
INSERT INTO posting_credit (posting_base_id, credit_accountid, credit_amount)
VALUES (13, 2, '100'::MONEY);
INSERT INTO posting_credit (posting_base_id, credit_accountid, credit_amount)
VALUES (13, 4, '100'::MONEY);
UPDATE posting_base SET complete = TRUE where id = 13;
/* ACCOUNTING VIEW SCHEMA */
INSERT INTO accounting_view.journal_charge
    (id, occurred, complete, debit_posting_id, debit_accountid, posting_id, credit_accountid, credit_amount)
    VALUES (11, '2021-01-06'::DATE, TRUE, 21, 2, 22, 3, '100'::MONEY);
INSERT INTO accounting_view.journal_charge
    (id, occurred, complete, debit_posting_id, debit_accountid, posting_id, credit_accountid, credit_amount)
    VALUES (12, '2021-01-07'::DATE, TRUE, 23, 4, 24, 3, '100'::MONEY);
INSERT INTO accounting_view.journal_payment
    (id, occurred, complete, debit_posting_id, debit_accountid, posting_id, credit_accountid, credit_amount)
    VALUES (13, '2021-01-13'::DATE, TRUE, 25, 1, 26, 2, '100'::MONEY);
INSERT INTO accounting_view.journal_payment
    (id, occurred, complete, debit_posting_id, debit_accountid, posting_id, credit_accountid, credit_amount)
    VALUES (13, '2021-01-13'::DATE, TRUE, 25, 1, 27, 4, '100'::MONEY);
/* * INVOICE SCHEMA * */
INSERT INTO invoice.invoice (memberid) VALUES (5035);
INSERT INTO invoice.invoice_component(invoice_id, posting_id)
    VALUES (5, 22);
INSERT INTO invoice.invoice_component(invoice_id, posting_id)
    VALUES (5, 24);
INSERT INTO invoice.payment (memberid) VALUES (5035);
INSERT INTO invoice.payment_component(payment_id, posting_id)
    VALUES (5, 26);
INSERT INTO invoice.payment_component(payment_id, posting_id)
    VALUES (5, 27);
INSERT INTO invoice.invoice_payment(payment_component_id, invoice_component_id)
    VALUES (6, 6);
INSERT INTO invoice.invoice_payment(payment_component_id, invoice_component_id)
    VALUES (7, 7);
