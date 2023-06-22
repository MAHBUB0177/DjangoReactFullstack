--
-- PostgreSQL database dump
--

-- Dumped from database version 12.13
-- Dumped by pg_dump version 12.13

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: adminpack; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS adminpack WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION adminpack; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION adminpack IS 'administrative functions for PostgreSQL';


--
-- Name: center_days_of_month; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.center_days_of_month AS (
	center_week character varying(20),
	center_begin_date date,
	center_date date
);


ALTER TYPE public.center_days_of_month OWNER TO postgres;

--
-- Name: charge_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.charge_type AS (
	charges_id character varying(20),
	charges_code character varying(20),
	charges_name character varying(200),
	charge_amount numeric(22,2)
);


ALTER TYPE public.charge_type OWNER TO postgres;

--
-- Name: fn_delar_client_center_transfer(character, character); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_delar_client_center_transfer(p_client_id character, p_new_center_code character, OUT o_status character, OUT o_errm character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_errm              VARCHAR;
   w_status            VARCHAR;
   client_info         RECORD;
   account_info        RECORD;
   w_center_code       INTEGER;
   w_old_center_code   VARCHAR;
BEGIN
   BEGIN
      SELECT center_code
        INTO STRICT w_center_code
        FROM delar_center
       WHERE center_code = p_new_center_code;
   EXCEPTION
      WHEN NO_DATA_FOUND
      THEN
         w_status := 'E';
         w_errm := 'Invalid Center Code!';
         RAISE EXCEPTION USING MESSAGE = w_errm;
   END;

   FOR client_info IN (SELECT client_id, center_code
                         FROM sales_clients
                        WHERE client_id = p_client_id)
   LOOP
      w_old_center_code := client_info.center_code;

      UPDATE sales_clients
         SET center_code = p_new_center_code
       WHERE client_id = client_info.client_id;

      UPDATE sales_sales_master
         SET center_code = p_new_center_code
       WHERE customer_id = p_client_id;

      UPDATE sales_sales_return_details
         SET center_code = p_new_center_code
       WHERE client_id = p_client_id;

      UPDATE sales_order_master
         SET center_code = p_new_center_code
       WHERE customer_id = p_client_id;

      UPDATE sales_sales_details
         SET center_code = p_new_center_code
       WHERE client_id = p_client_id;

      UPDATE sales_emi_setup
         SET center_code = p_new_center_code
       WHERE client_id = p_client_id;

      UPDATE sales_fees_history
         SET center_code = p_new_center_code
       WHERE client_id = p_client_id;

   END LOOP;

   FOR account_info IN (SELECT account_number, client_id
                          FROM finance_accounts_balance
                         WHERE client_id = p_client_id)
   LOOP
      UPDATE finance_accounts_balance
         SET center_code = p_new_center_code
       WHERE client_id = p_client_id;

      UPDATE finance_transaction_details
         SET center_code = p_new_center_code
       WHERE account_number = account_info.account_number;

      UPDATE finance_deposit_receive
         SET center_code = p_new_center_code
       WHERE account_number = account_info.account_number;

      UPDATE finance_deposit_payment
         SET center_code = p_new_center_code
       WHERE account_number = account_info.account_number;

      UPDATE sales_emi_receive
         SET center_code = p_new_center_code
       WHERE account_number = account_info.account_number;

      UPDATE sales_emi_history
         SET center_code = p_new_center_code
       WHERE account_number = account_info.account_number;
   END LOOP;

   BEGIN
      INSERT INTO delar_client_center_trf_hist (client_id,
                                                 old_center_code,
                                                 new_center_code,
                                                 app_data_time)
           VALUES (p_client_id,
                   w_old_center_code,
                   p_new_center_code,
                   current_timestamp);
   END;

   o_status := 'S';
   o_errm := '';
EXCEPTION
   WHEN OTHERS
   THEN
      IF w_status = 'E'
      THEN
         o_status := w_status;
         o_errm := w_errm;
      ELSE
         o_errm := SQLERRM;
         o_status := 'E';
      END IF;
END;
$$;


ALTER FUNCTION public.fn_delar_client_center_transfer(p_client_id character, p_new_center_code character, OUT o_status character, OUT o_errm character) OWNER TO postgres;

--
-- Name: fn_delar_srstage_post(integer, date, character, character); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_delar_srstage_post(p_branch_code integer, p_invoice_date date, p_employee_id character, p_app_user_id character, OUT o_status character, OUT o_errm character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_error_message              VARCHAR;
   w_batch_number               INTEGER;
   w_check                      BOOLEAN;
   w_account_number             VARCHAR := '0';
   w_transaction_date           DATE;
   product_list                 RECORD;
   w_tran_gl_code               VARCHAR := '0';
   w_cash_transaction           BOOLEAN;
   w_total_leg                  INTEGER;
   w_total_debit_amount         NUMERIC (22, 2) := 0;
   w_total_credit_amount        NUMERIC (22, 2) := 0;
   w_account_banalce            NUMERIC (22, 2) := 0;
   w_credit_limit               NUMERIC (22, 2) := 0;
   w_serial_no                  INTEGER := 0;
   w_product_total_stock        INTEGER := 0;
   w_product_total_sales        INTEGER := 0;
   w_product_available_stock    INTEGER := 0;
   w_product_last_stock_date    DATE;
   w_product_last_sale_date     DATE;
   w_product_last_return_date   DATE;
   w_product_total_returned     INTEGER := 0;
   w_total_purchase_amount      NUMERIC (22, 2) := 0.00;
   w_total_return_amount        NUMERIC (22, 2) := 0.00;
   w_total_sales_amount         NUMERIC (22, 2) := 0.00;
   w_product_total_damage       INTEGER := 0;
   w_total_return_damage        NUMERIC (22, 2) := 0.00;
   w_last_order_date            DATE;
   w_total_order_quantity       INTEGER := 0;
   w_total_bill_amount          NUMERIC (22, 2) := 0.00;
   w_bill_amount                NUMERIC (22, 2) := 0.00;
   w_due_amount                 NUMERIC (22, 2) := 0.00;
   w_advance_pay                NUMERIC (22, 2) := 0.00;
   w_status                     VARCHAR;
   w_errm                       VARCHAR;
   w_product_name               VARCHAR;
   w_tran_debit_account_type    VARCHAR;
   w_invoice_number             VARCHAR;
   w_last_balance_update        DATE;
   w_last_transaction_date      DATE;
BEGIN
   w_last_order_date := p_invoice_date;

   BEGIN
      SELECT invoice_number
       INTO STRICT w_invoice_number
       FROM delar_srstage_master
      WHERE     branch_code = p_branch_code
            AND invoice_date = p_invoice_date
            AND employee_id = p_employee_id;
   EXCEPTION
      WHEN no_data_found
      THEN
         w_invoice_number :=
            fn_get_inventory_number (40004,
                                     100,
                                     'SR',
                                     'Sales Representative Number Generate',
                                     8);
   END;

   FOR product_list
      IN (  SELECT s.invoice_number,
                   s.product_id,
                   s.product_bar_code,
                   s.product_model,
                   s.product_name,
                   s.product_price,
                   s.quantity,
                   s.total_price,
                   s.profit_amount,
                   s.discount_rate,
                   s.discount_amount,
                   s.status,
                   s.comments,
                   s.app_user_id,
                   s.app_data_time
              FROM delar_srstage_details_temp s, sales_products p
             WHERE     p.product_id = s.product_id
                   AND s.app_user_id = p_app_user_id
          ORDER BY s.id)
   LOOP
      BEGIN
         w_total_order_quantity :=
            w_total_order_quantity + product_list.quantity;
         w_serial_no := w_serial_no + 1;
         w_total_bill_amount :=
            w_total_bill_amount + product_list.total_price;
         w_bill_amount :=
              w_bill_amount
            + product_list.total_price
            - product_list.discount_amount;

         BEGIN
            SELECT invoice_number
             INTO STRICT w_invoice_number
             FROM delar_srstage_details
            WHERE     branch_code = p_branch_code
                  AND invoice_date = p_invoice_date
                  AND product_id = product_list.product_id
                  AND employee_id = p_employee_id;

            UPDATE delar_srstage_details
               SET product_price = product_price + product_list.product_price,
                   quantity = quantity + product_list.quantity,
                   total_price = total_price + product_list.total_price,
                   profit_amount = profit_amount + product_list.profit_amount,
                   discount_amount =
                      discount_amount + product_list.discount_amount
             WHERE     branch_code = p_branch_code
                   AND invoice_date = p_invoice_date
                   AND product_id = product_list.product_id
                   AND employee_id = p_employee_id;
         EXCEPTION
            WHEN no_data_found
            THEN
               INSERT INTO delar_srstage_details (branch_code,
                                                  invoice_number,
                                                  invoice_date,
                                                  employee_id,
                                                  product_id,
                                                  product_price,
                                                  quantity,
                                                  total_price,
                                                  profit_amount,
                                                  discount_rate,
                                                  discount_amount,
                                                  status,
                                                  comments,
                                                  sales_amount,
                                                  sales_discount_amount,
                                                  sales_quantity,
                                                  app_user_id,
                                                  app_data_time)
                    VALUES (p_branch_code,
                            w_invoice_number,
                            p_invoice_date,
                            p_employee_id,
                            product_list.product_id,
                            product_list.product_price,
                            product_list.quantity,
                            product_list.total_price,
                            product_list.profit_amount,
                            product_list.discount_rate,
                            product_list.discount_amount,
                            'I',
                            product_list.comments,
                            0.00,
                            0.00,
                            0,
                            product_list.app_user_id,
                            current_timestamp);
         END;
      END;

      BEGIN
         SELECT product_available_stock,
                inv_balance_upto_date,
                COALESCE (last_sale_date, p_invoice_date) last_sale_date
           INTO w_product_available_stock,
                w_last_balance_update,
                w_last_transaction_date
           FROM sales_products_inventory_status
          WHERE     product_id = product_list.product_id
                AND branch_code = p_branch_code;

         /*
                  UPDATE sales_products_inventory_status
                     SET product_quantity_in_sr =
                            product_quantity_in_sr + product_list.quantity,
                         last_sale_date = w_last_transaction_date,
                         inv_balance_upto_date = w_last_balance_update
                   WHERE     product_id = product_list.product_id
                         AND branch_code = p_branch_code;
         */
         SELECT product_name
           INTO w_product_name
           FROM sales_products
          WHERE product_id = product_list.product_id;
      END;

      IF w_product_available_stock - product_list.quantity < 0
      THEN
         w_status := 'E';
         w_errm := 'Product ' || w_product_name || ' Out of Stock!';
         RAISE EXCEPTION USING MESSAGE = w_errm;
      END IF;

      BEGIN
         SELECT product_available_stock,
                inv_balance_upto_date,
                COALESCE (last_sale_date, p_invoice_date) last_sale_date
           INTO STRICT w_product_available_stock,
                       w_last_balance_update,
                       w_last_transaction_date
           FROM delar_srstage_inventory_status
          WHERE     product_id = product_list.product_id
                AND employee_id = p_employee_id;

         w_last_balance_update :=
            LEAST (p_invoice_date, w_last_balance_update);
         w_last_transaction_date :=
            GREATEST (p_invoice_date, w_last_balance_update);

         UPDATE delar_srstage_inventory_status
            SET product_total_stock =
                   product_total_stock + product_list.quantity,
                product_available_stock =
                   product_available_stock + product_list.quantity,
                total_purchase_amount =
                   total_purchase_amount + product_list.total_price,
                last_stock_date = w_last_transaction_date,
                inv_balance_upto_date = w_last_balance_update
          WHERE     product_id = product_list.product_id
                AND employee_id = p_employee_id;
      EXCEPTION
         WHEN NO_DATA_FOUND
         THEN
            INSERT INTO delar_srstage_inventory_status (
                           branch_code,
                           employee_id,
                           product_id,
                           product_total_stock,
                           total_order_quantity,
                           product_total_sales,
                           total_stock_return,
                           total_sales_return,
                           product_total_damage,
                           product_available_stock,
                           product_purchase_rate,
                           last_stock_date,
                           last_order_date,
                           last_sale_date,
                           last_stock_return_date,
                           last_sales_return_date,
                           last_damage_date,
                           inv_balance_upto_date,
                           total_purchase_amount,
                           total_sales_amount,
                           stock_return_amount,
                           sales_return_amount,
                           total_damage_amount,
                           damage_receive_amount,
                           cost_of_good_sold,
                           total_discount_receive,
                           total_discount_pay,
                           packet_payment_value,
                           packet_receive_value,
                           total_packet_payment,
                           total_packet_receive,
                           app_user_id,
                           app_data_time)
                 VALUES (p_branch_code,
                         p_employee_id,
                         product_list.product_id,
                         product_list.quantity,
                         0,
                         0,
                         0,
                         0,
                         0,
                         product_list.quantity,
                         0.00,
                         p_invoice_date,
                         NULL,
                         NULL,
                         NULL,
                         NULL,
                         NULL,
                         p_invoice_date - 1,
                         product_list.total_price,
                         0.00,
                         0.00,
                         0.00,
                         0.00,
                         0.00,
                         0.00,
                         0.00,
                         0.00,
                         0.00,
                         0.00,
                         0,
                         0,
                         p_app_user_id,
                         current_timestamp);
      END;

      BEGIN
         UPDATE delar_srstage_inventory_sum
            SET product_total_stock =
                   product_total_stock + product_list.quantity,
                product_available_stock =
                   product_available_stock + product_list.quantity,
                total_purchase_amount =
                   total_purchase_amount + product_list.total_price
          WHERE employee_id = p_employee_id;
      EXCEPTION
         WHEN NO_DATA_FOUND
         THEN
            INSERT INTO delar_srstage_inventory_sum (employee_id,
                                                     product_total_stock,
                                                     total_order_quantity,
                                                     product_total_sales,
                                                     total_stock_return,
                                                     total_sales_return,
                                                     product_total_damage,
                                                     product_available_stock,
                                                     total_purchase_amount,
                                                     total_sales_amount,
                                                     stock_return_amount,
                                                     sales_return_amount,
                                                     total_damage_amount,
                                                     damage_receive_amount,
                                                     cost_of_good_sold,
                                                     total_discount_receive,
                                                     total_discount_pay,
                                                     packet_payment_value,
                                                     packet_receive_value,
                                                     total_packet_payment,
                                                     total_packet_receive,
                                                     app_user_id,
                                                     app_data_time)
                 VALUES (p_employee_id,
                         product_list.quantity,
                         0,
                         0,
                         0,
                         0,
                         0,
                         product_list.quantity,
                         product_list.total_price,
                         0.00,
                         0.00,
                         0.00,
                         0.00,
                         0.00,
                         0.00,
                         0.00,
                         0.00,
                         0.00,
                         0.00,
                         0,
                         0,
                         p_app_user_id,
                         current_timestamp);
      END;
   END LOOP;

   BEGIN
      SELECT invoice_number
       INTO STRICT w_invoice_number
       FROM delar_srstage_master
      WHERE     branch_code = p_branch_code
            AND invoice_date = p_invoice_date
            AND employee_id = p_employee_id;

      UPDATE delar_srstage_master
         SET total_bill_amount = total_bill_amount + w_total_bill_amount,
             total_quantity = total_quantity + w_total_order_quantity,
             bill_amount = bill_amount + w_bill_amount,
             due_amount = due_amount + w_due_amount,
             advance_pay = advance_pay + w_advance_pay
       WHERE     branch_code = p_branch_code
             AND invoice_date = p_invoice_date
             AND employee_id = p_employee_id;
   EXCEPTION
      WHEN no_data_found
      THEN
         INSERT INTO delar_srstage_master (branch_code,
                                           invoice_number,
                                           invoice_date,
                                           employee_id,
                                           total_quantity,
                                           returned_quantity,
                                           total_bill_amount,
                                           bill_amount,
                                           pay_amount,
                                           due_amount,
                                           advance_pay,
                                           status,
                                           invoice_comments,
                                           total_sales_amount,
                                           total_sales_discount_amount,
                                           total_sales_quantity,
                                           app_user_id,
                                           app_data_time)
              VALUES (p_branch_code,
                      w_invoice_number,
                      p_invoice_date,
                      p_employee_id,
                      w_total_order_quantity,
                      0,
                      w_total_bill_amount,
                      w_bill_amount,
                      0,
                      w_due_amount,
                      w_advance_pay,
                      'S',
                      'NA',
                      0.00,
                      0.00,
                      0,
                      p_app_user_id,
                      current_timestamp);
   END;

   DELETE FROM delar_srstage_details_temp s
         WHERE s.app_user_id = p_app_user_id;

   o_status := 'S';
   o_errm := '';
EXCEPTION
   WHEN OTHERS
   THEN
      IF w_status = 'E'
      THEN
         o_status := w_status;
         o_errm := w_errm;
      ELSE
         o_status := 'E';
         o_errm := SQLERRM;
      END IF;
END;
$$;


ALTER FUNCTION public.fn_delar_srstage_post(p_branch_code integer, p_invoice_date date, p_employee_id character, p_app_user_id character, OUT o_status character, OUT o_errm character) OWNER TO postgres;

--
-- Name: fn_fin_check_day_month_year(character, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_fin_check_day_month_year(p_frequenct character, p_date date) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_month_end         DATE;
   w_quarter_end       DATE;
   w_half_year_end     DATE;
   w_year_end          DATE;
   w_month_start       DATE;
   w_quarter_start     DATE;
   w_half_year_start   DATE;
   w_year_start        DATE;
BEGIN
   SELECT CAST (
               date_trunc ('month', p_date)
             + INTERVAL '1 months'
             - INTERVAL '1 day' AS DATE)
             month_end,
          CAST (
               date_trunc ('quarter', p_date)
             + INTERVAL '3 months'
             - INTERVAL '1 day' AS DATE)
             quarter_end,
          CAST (
               date_trunc ('year', p_date)
             + INTERVAL '6 months'
             - INTERVAL '1 day' AS DATE)
             half_year_end,
          CAST (
               date_trunc ('year', p_date)
             + INTERVAL '12 months'
             - INTERVAL '1 day' AS DATE)
             year_end,
          CAST (date_trunc ('month', p_date) AS DATE)
             month_start,
          CAST (date_trunc ('quarter', p_date) AS DATE)
             quarter_start,
          CAST (
             CAST (EXTRACT (YEAR FROM p_date) AS INTEGER) || '-07-01' AS DATE)
             half_year_start,
          CAST (date_trunc ('year', p_date) AS DATE)
             year_start
     INTO w_month_end,
          w_quarter_end,
          w_half_year_end,
          w_year_end,
          w_month_start,
          w_quarter_start,
          w_half_year_start,
          w_year_start;

   IF p_frequenct = 'D'
   THEN
      RETURN TRUE;
   END IF;

   IF p_frequenct = 'M'
   THEN
      IF w_month_end = p_date
      THEN
         RETURN TRUE;
      END IF;
   END IF;

   IF p_frequenct = 'Q'
   THEN
      IF w_quarter_end = p_date
      THEN
         RETURN TRUE;
      END IF;
   END IF;

   IF p_frequenct = 'H'
   THEN
      IF w_half_year_end = p_date
      THEN
         RETURN TRUE;
      END IF;
   END IF;

   IF p_frequenct = 'Y'
   THEN
      IF w_year_end = p_date
      THEN
         RETURN TRUE;
      END IF;
   END IF;

   RETURN FALSE;
EXCEPTION
   WHEN OTHERS
   THEN
      RETURN FALSE;
END;
$$;


ALTER FUNCTION public.fn_fin_check_day_month_year(p_frequenct character, p_date date) OWNER TO postgres;

--
-- Name: fn_finance_acbal_hist(character, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_finance_acbal_hist(p_account_number character, p_ason_date date, OUT o_status character, OUT o_errm character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   rec_account_list         RECORD;
   rec_date_list            RECORD;
   w_calculate_date         DATE;
   w_current_business_day   DATE;
   w_total_debit_sum        NUMERIC (22, 2) := 0;
   w_total_credit_sum       NUMERIC (22, 2) := 0;
   w_account_balance        NUMERIC (22, 2) := 0;
   w_account_balance_prev   NUMERIC (22, 2) := 0;
   w_cum_debit_sum          NUMERIC (22, 2) := 0;
   w_cum_credit_sum         NUMERIC (22, 2) := 0;
   w_charge_banalce         NUMERIC (22, 2) := 0;
   w_status                 VARCHAR;
   w_errm                   VARCHAR;
BEGIN
   FOR rec_account_list
      IN (SELECT branch_code,
                 account_number,
                 account_balance,
                 last_transaction_date,
                 last_balance_update
            FROM finance_accounts_balance
           WHERE account_number = p_account_number AND NOT is_balance_updated)
   LOOP
      w_calculate_date := rec_account_list.last_balance_update;

      BEGIN
         SELECT o_account_balance, o_total_credit, o_total_debit
           INTO w_account_balance, w_cum_credit_sum, w_cum_debit_sum
           FROM fn_finance_get_ason_acbal (rec_account_list.account_number,
                                           w_calculate_date - 1);
      END;

      FOR rec_date_list
         IN (  SELECT transaction_date,
                      COALESCE (SUM (debit_amount), 0.00) total_debit_amount,
                      COALESCE (sum (credit_amount), 0.00) total_credit_amount
                 FROM (SELECT transaction_date,
                              (CASE
                                  WHEN tran_debit_credit = 'D' THEN tran_amount
                                  ELSE 0
                               END) debit_amount,
                              (CASE
                                  WHEN tran_debit_credit = 'C' THEN tran_amount
                                  ELSE 0
                               END) credit_amount
                         FROM finance_transaction_details S
                        WHERE     account_number = p_account_number
                              AND s.cancel_by IS NULL
                              AND transaction_date >
                                  rec_account_list.last_balance_update - 1) T
             GROUP BY transaction_date
             ORDER BY transaction_date)
      LOOP
         w_calculate_date := rec_date_list.transaction_date;
         w_total_credit_sum := rec_date_list.total_credit_amount;
         w_total_debit_sum := rec_date_list.total_debit_amount;
         w_cum_credit_sum :=
            w_cum_credit_sum + rec_date_list.total_credit_amount;
         w_cum_debit_sum :=
            w_cum_debit_sum + rec_date_list.total_debit_amount;
         w_account_balance :=
            w_account_balance + (w_total_credit_sum - w_total_debit_sum);

         DELETE FROM finance_accounts_balance_hist
               WHERE     account_number = rec_account_list.account_number
                     AND transaction_date = w_calculate_date;

         INSERT INTO finance_accounts_balance_hist (branch_code,
                                                    account_number,
                                                    transaction_date,
                                                    total_debit_sum,
                                                    total_credit_sum,
                                                    account_balance,
                                                    cum_debit_sum,
                                                    cum_credit_sum,
                                                    app_user_id,
                                                    app_data_time)
              VALUES (rec_account_list.branch_code,
                      rec_account_list.account_number,
                      w_calculate_date,
                      COALESCE (w_total_debit_sum, 0, 00),
                      COALESCE (w_total_credit_sum, 0.00),
                      COALESCE (w_account_balance, 0.00),
                      COALESCE (w_cum_debit_sum, 0.00),
                      COALESCE (w_cum_credit_sum, 0.00),
                      'SYSTEM',
                      current_timestamp);
      END LOOP;

      UPDATE finance_accounts_balance
         SET last_balance_update = w_calculate_date,
             is_balance_updated = TRUE
       WHERE account_number = p_account_number;
   END LOOP;


   o_status := 'S';
   o_errm := '';
EXCEPTION
   WHEN OTHERS
   THEN
      IF w_status = 'E'
      THEN
         o_status := w_status;
         o_errm := w_errm;
      ELSE
         o_status := 'E';
         o_errm := SQLERRM;
      END IF;
END;
$$;


ALTER FUNCTION public.fn_finance_acbal_hist(p_account_number character, p_ason_date date, OUT o_status character, OUT o_errm character) OWNER TO postgres;

--
-- Name: fn_finance_balance_history(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_finance_balance_history(p_branch_code integer, OUT o_status character, OUT o_errm character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_status                 VARCHAR;
   w_errm                   VARCHAR;
   w_current_business_day   DATE;
   rec_gl_list              RECORD;
   rec_account_list         RECORD;
   w_account_number         VARCHAR;
BEGIN
   FOR rec_account_list
      IN (SELECT branch_code,
                 account_number,
                 account_balance,
                 last_transaction_date,
                 last_balance_update
            FROM finance_accounts_balance
           WHERE branch_code = p_branch_code AND NOT is_balance_updated)
   LOOP
      w_account_number := rec_account_list.account_number;

      BEGIN
         SELECT *
         INTO w_status, w_errm
         FROM fn_finance_acbal_hist (rec_account_list.account_number,
                                     rec_account_list.last_transaction_date);

         IF w_status = 'E'
         THEN
            RAISE EXCEPTION
            USING MESSAGE =
                        'Error From Account Balance History for Account'
                     || rec_account_list.account_number
                     || ' '
                     || w_errm;
         END IF;
      END;
   END LOOP;

   o_status := 'S';
   o_errm := '';
EXCEPTION
   WHEN OTHERS
   THEN
      IF w_status = 'E'
      THEN
         o_status := w_status;
         o_errm := w_errm;
      ELSE
         o_errm := SQLERRM;
         o_status := 'E';
      END IF;
END;
$$;


ALTER FUNCTION public.fn_finance_balance_history(p_branch_code integer, OUT o_status character, OUT o_errm character) OWNER TO postgres;

--
-- Name: fn_finance_get_ason_acbal(character, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_finance_get_ason_acbal(p_account_number character, p_ason_date date, OUT o_account_balance numeric, OUT o_block_amount numeric, OUT o_total_credit numeric, OUT o_total_debit numeric) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_current_business_day       DATE;
   w_account_balance            NUMERIC (22, 2) := 0;
   W_minimum_balance_required   NUMERIC (22, 2) := 0;
   w_total_credit               NUMERIC (22, 2) := 0;
   w_total_debit                NUMERIC (22, 2) := 0;
   w_products_type              CHARACTER (10);
   w_phone_number               CHARACTER (20);
   w_total_block_amount         NUMERIC (22, 2) := 0;
   w_status                     VARCHAR;
   w_errm                       VARCHAR;
   w_last_balance_update        DATE;
   w_last_transaction_date      DATE;
BEGIN
   SELECT account_balance,
          total_debit_amount,
          total_credit_amount,
          account_type,
          phone_number,
          last_balance_update,
          last_transaction_date
     INTO w_account_balance,
          w_total_debit,
          w_total_credit,
          w_products_type,
          w_phone_number,
          w_last_balance_update,
          w_last_transaction_date
     FROM finance_accounts_balance
    WHERE account_number = p_account_number;

   IF     w_last_balance_update = w_last_transaction_date
      AND p_ason_date = w_last_transaction_date
   THEN
      w_account_balance := w_account_balance;
   ELSE
      SELECT account_balance, cum_debit_sum, cum_credit_sum
        INTO w_account_balance, w_total_debit, w_total_credit
        FROM finance_accounts_balance_hist h
       WHERE     h.account_number = p_account_number
             AND h.transaction_date =
                 (SELECT max (transaction_date)
                   FROM finance_accounts_balance_hist
                  WHERE     account_number = p_account_number
                        AND transaction_date <= p_ason_date);
   END IF;

   o_account_balance := COALESCE (w_account_balance, 0.00);
   o_block_amount := COALESCE (w_total_block_amount, 0.00);
   o_total_credit := COALESCE (w_total_credit, 0.00);
   o_total_debit := COALESCE (w_total_debit, 0.00);
END;
$$;


ALTER FUNCTION public.fn_finance_get_ason_acbal(p_account_number character, p_ason_date date, OUT o_account_balance numeric, OUT o_block_amount numeric, OUT o_total_credit numeric, OUT o_total_debit numeric) OWNER TO postgres;

--
-- Name: fn_finance_get_ason_glbal(integer, character, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_finance_get_ason_glbal(p_branch_code integer, p_gl_code character, p_ason_date date, OUT o_gl_balance numeric, OUT o_gl_credit numeric, OUT o_gl_debit numeric, OUT o_block_amount numeric, OUT o_status character, OUT o_errm character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_ledger_banalce          NUMERIC (22, 2) := 0;
   w_credit_banalce          NUMERIC (22, 2) := 0;
   w_debit_banalce           NUMERIC (22, 2) := 0;
   w_last_balance_update     DATE;
   w_last_transaction_date   DATE;
   w_status                  VARCHAR;
   w_errm                    VARCHAR;
BEGIN
   o_gl_balance := w_ledger_banalce;
   o_gl_credit := COALESCE (w_credit_banalce, 0.00);
   o_gl_debit := COALESCE (w_debit_banalce, 0.00);
   o_block_amount := 0.00;

   IF p_branch_code = 0
   THEN
      SELECT sum (gl_balance),
             sum (total_credit_sum),
             sum (total_debit_sum),
             min (last_balance_update),
             max (last_transaction_date)
        INTO w_ledger_banalce,
             w_credit_banalce,
             w_debit_banalce,
             w_last_balance_update,
             w_last_transaction_date
        FROM finance_ledger_balance
       WHERE gl_code = p_gl_code;

      IF     w_last_balance_update = w_last_transaction_date
         AND p_ason_date = w_last_transaction_date
      THEN
         w_ledger_banalce := w_ledger_banalce;
      ELSE
         SELECT sum (gl_balance) gl_balance,
                sum (cum_credit_sum),
                sum (cum_debit_sum)
           INTO w_ledger_banalce, w_credit_banalce, w_debit_banalce
           FROM finance_ledger_balance_hist h,
                (  SELECT branch_code,
                          max (transaction_date) last_transaction_date
                     FROM finance_ledger_balance_hist g
                    WHERE     g.gl_code = p_gl_code
                          AND transaction_date <= p_ason_date
                 GROUP BY branch_code) b
          WHERE     h.gl_code = p_gl_code
                AND h.transaction_date = b.last_transaction_date
                AND h.branch_code = b.branch_code;
      END IF;
   ELSIF p_branch_code > 0
   THEN
      SELECT sum (gl_balance),
             sum (total_credit_sum),
             sum (total_debit_sum),
             min (last_balance_update),
             max (last_transaction_date)
        INTO w_ledger_banalce,
             w_credit_banalce,
             w_debit_banalce,
             w_last_balance_update,
             w_last_transaction_date
        FROM finance_ledger_balance
       WHERE gl_code = p_gl_code AND branch_code = p_branch_code;


      IF     w_last_balance_update = w_last_transaction_date
         AND p_ason_date = w_last_transaction_date
      THEN
         w_ledger_banalce := w_ledger_banalce;
      ELSE
         SELECT sum (gl_balance) gl_balance,
                sum (cum_credit_sum),
                sum (cum_debit_sum)
           INTO w_ledger_banalce, w_credit_banalce, w_debit_banalce
           FROM finance_ledger_balance_hist h,
                (  SELECT branch_code,
                          max (transaction_date) last_transaction_date
                     FROM finance_ledger_balance_hist g
                    WHERE     g.gl_code = p_gl_code
                          AND g.branch_code = p_branch_code
                          AND g.transaction_date <= p_ason_date
                 GROUP BY branch_code) b
          WHERE     h.gl_code = p_gl_code
                AND h.branch_code = p_branch_code
                AND h.transaction_date = b.last_transaction_date
                AND h.branch_code = b.branch_code;
      END IF;
   END IF;

   w_ledger_banalce := COALESCE (w_ledger_banalce, 0.00);

   o_gl_balance := w_ledger_banalce;
   o_gl_credit := COALESCE (w_credit_banalce, 0.00);
   o_gl_debit := COALESCE (w_debit_banalce, 0.00);
   o_block_amount := 0.00;
EXCEPTION
   WHEN OTHERS
   THEN
      IF w_status = 'E'
      THEN
         o_status := w_status;
         o_errm := w_errm;
      ELSE
         o_errm := SQLERRM;
         o_status := 'E';
      END IF;
END;
$$;


ALTER FUNCTION public.fn_finance_get_ason_glbal(p_branch_code integer, p_gl_code character, p_ason_date date, OUT o_gl_balance numeric, OUT o_gl_credit numeric, OUT o_gl_debit numeric, OUT o_block_amount numeric, OUT o_status character, OUT o_errm character) OWNER TO postgres;

--
-- Name: fn_finance_get_charges(numeric, character, character, boolean, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_finance_get_charges(p_amount numeric DEFAULT 0, p_actype_code character DEFAULT ''::bpchar, p_charge_code character DEFAULT ''::bpchar, p_account_opening boolean DEFAULT false, p_account_closing boolean DEFAULT false) RETURNS SETOF public.charge_type
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_status                 VARCHAR;
   w_errm                   VARCHAR;
   w_current_business_day   DATE;
   result_record            charge_type;
   rec_open_list            RECORD;
BEGIN
   /*
   CREATE TYPE charge_type AS (charges_code varchar(20), charge_amount NUMERIC (22, 2));

   result_record.charges_code := '1';
   result_record.charge_amount := '1';
   RETURN NEXT
      result_record;

   result_record.charges_code := '2';
   result_record.charge_amount := '2';
   RETURN NEXT
      result_record;
   */

   IF CHAR_LENGTH (p_charge_code) > 1
   THEN
      FOR rec_open_list
         IN (SELECT charges_id,
                    charges_code,
                    charges_name,
                    charge_amount,
                    charge_type,
                    charge_percentage
               FROM finance_charges
              WHERE     charges_code = p_charge_code
                    AND p_amount BETWEEN charge_from_amount
                                     AND charge_upto_amount)
      LOOP
         IF rec_open_list.charge_type = 'F'
         THEN
            result_record.charges_id := rec_open_list.charges_id;
            result_record.charges_code := rec_open_list.charges_code;
            result_record.charges_name := rec_open_list.charges_name;
            result_record.charge_amount := rec_open_list.charge_amount;
            RETURN NEXT
               result_record;
         ELSE
            result_record.charges_id := rec_open_list.charges_id;
            result_record.charges_code := rec_open_list.charges_code;
            result_record.charges_name := rec_open_list.charges_name;
            result_record.charge_amount :=
               (p_amount * (rec_open_list.charge_percentage / 100));
            RETURN NEXT
               result_record;
         END IF;
      END LOOP;
   ELSE
      IF p_account_opening
      THEN
         FOR rec_open_list
            IN (SELECT charges_id,
                       charges_code,
                       charges_name,
                       charge_amount,
                       charge_type,
                       charge_percentage
                  FROM finance_charges
                 WHERE     actype_code = p_actype_code
                       AND account_opening_charge = p_account_opening
                       AND p_amount BETWEEN charge_from_amount
                                        AND charge_upto_amount)
         LOOP
            IF rec_open_list.charge_type = 'F'
            THEN
               result_record.charges_id := rec_open_list.charges_id;
               result_record.charges_code := rec_open_list.charges_code;
               result_record.charges_name := rec_open_list.charges_name;
               result_record.charge_amount := rec_open_list.charge_amount;
               RETURN NEXT
                  result_record;
            ELSE
               result_record.charges_id := rec_open_list.charges_id;
               result_record.charges_code := rec_open_list.charges_code;
               result_record.charges_name := rec_open_list.charges_name;
               result_record.charge_amount :=
                  (p_amount * (rec_open_list.charge_percentage / 100));
               RETURN NEXT
                  result_record;
            END IF;
         END LOOP;
      END IF;

      IF p_account_closing
      THEN
         FOR rec_open_list
            IN (SELECT charges_id,
                       charges_code,
                       charges_name,
                       charge_amount,
                       charge_type,
                       charge_percentage
                  FROM finance_charges
                 WHERE     actype_code = p_actype_code
                       AND account_closing_charge = p_account_closing
                       AND p_amount BETWEEN charge_from_amount
                                        AND charge_upto_amount)
         LOOP
            IF rec_open_list.charge_type = 'F'
            THEN
               result_record.charges_id := rec_open_list.charges_id;
               result_record.charges_code := rec_open_list.charges_code;
               result_record.charges_name := rec_open_list.charges_name;
               result_record.charge_amount := rec_open_list.charge_amount;
               RETURN NEXT
                  result_record;
            ELSE
               result_record.charges_id := rec_open_list.charges_id;
               result_record.charges_code := rec_open_list.charges_code;
               result_record.charges_name := rec_open_list.charges_name;
               result_record.charge_amount :=
                  (p_amount * (rec_open_list.charge_percentage / 100));
               RETURN NEXT
                  result_record;
            END IF;
         END LOOP;
      END IF;
   END IF;

   RETURN;
EXCEPTION
   WHEN OTHERS
   THEN
      NULL;
END;
$$;


ALTER FUNCTION public.fn_finance_get_charges(p_amount numeric, p_actype_code character, p_charge_code character, p_account_opening boolean, p_account_closing boolean) OWNER TO postgres;

--
-- Name: fn_finance_post_cash_tran(integer, character, character, character, character, date, character, character, character); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_finance_post_cash_tran(p_branch_code integer, p_center_code character, p_app_user_id character, p_transaction_type character, p_transaction_ledger character, p_tran_date date, p_tran_narration character, p_receive_payment character, p_tran_source character, OUT o_status character, OUT o_errm character, OUT o_batch_number character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_error_message         VARCHAR;
   w_batch_number          INTEGER;
   w_check                 BOOLEAN;
   w_account_number        VARCHAR := '0';
   w_transaction_date      DATE;
   TRAN_DATA               RECORD;
   w_tran_gl_code          VARCHAR := '0';
   w_contra_gl_code        VARCHAR := '0';
   w_cash_transaction      BOOLEAN;
   w_total_leg             INTEGER;
   w_total_debit_amount    NUMERIC (22, 2) := 0;
   w_total_credit_amount   NUMERIC (22, 2) := 0;
   w_available_balance     NUMERIC (22, 2) := 0;
   w_tran_amount           NUMERIC (22, 2) := 0;
   w_batch_serial          INTEGER := 0;
   w_day_serial_no         INTEGER := 0;
   w_tran_debit_credit     VARCHAR;
   w_status                VARCHAR;
   w_errm                  VARCHAR;
BEGIN
     SELECT count (batch_serial) + 1
               batch_serial,
            SUM (
               (CASE WHEN tran_debit_credit = 'D' THEN tran_amount ELSE 0 END))
               debit_amount,
            SUM (
               (CASE WHEN tran_debit_credit = 'C' THEN tran_amount ELSE 0 END))
               credit_amount
       INTO w_batch_serial, w_total_debit_amount, w_total_credit_amount
       FROM finance_transaction_table S
      WHERE S.branch_code = p_branch_code AND S.app_user_id = p_app_user_id
   ORDER BY batch_serial;

   BEGIN
      SELECT cash_gl_code
        INTO w_tran_gl_code
        FROM appauth_user_settings
       WHERE app_user_id = p_app_user_id;
   END;

   IF w_batch_serial > 0
   THEN
      FOR TRAN_DATA
         IN (  SELECT tran_gl_code,
                      account_number,
                      count (batch_serial) batch_serial,
                      SUM (
                         (CASE
                             WHEN tran_debit_credit = 'D' THEN tran_amount
                             ELSE 0
                          END)) debit_amount,
                      SUM (
                         (CASE
                             WHEN tran_debit_credit = 'C' THEN tran_amount
                             ELSE 0
                          END)) credit_amount
                 FROM finance_transaction_table S
                WHERE S.app_user_id = p_app_user_id
             GROUP BY S.tran_gl_code, s.account_number
             ORDER BY batch_serial)
      LOOP
         w_batch_serial := TRAN_DATA.batch_serial + 1;
         w_account_number := TRAN_DATA.account_number;

         IF TRAN_DATA.debit_amount > 0.00
         THEN
            w_tran_debit_credit := 'C';
            w_tran_amount := TRAN_DATA.debit_amount;
         ELSE
            w_tran_debit_credit := 'D';
            w_tran_amount := TRAN_DATA.credit_amount;
         END IF;

         IF w_account_number != '0'
         THEN
            BEGIN
               SELECT account_ledger_code
                 INTO STRICT w_contra_gl_code
                 FROM finance_accounts_balance
                WHERE account_number = w_account_number;
            EXCEPTION
               WHEN NO_DATA_FOUND
               THEN
                  RAISE EXCEPTION USING MESSAGE = 'Invalid Account Number!';
            END;

            w_account_number := '0';
         ---RAISE EXCEPTION USING MESSAGE = w_contra_gl_code;
         ELSE
            w_contra_gl_code := TRAN_DATA.tran_gl_code;
         END IF;

         IF w_tran_amount > 0
         THEN
            INSERT INTO finance_transaction_table (branch_code,
                                                   center_code,
                                                   transaction_date,
                                                   batch_serial,
                                                   account_number,
                                                   tran_gl_code,
                                                   contra_gl_code,
                                                   tran_debit_credit,
                                                   tran_type,
                                                   tran_amount,
                                                   available_balance,
                                                   tran_person_phone,
                                                   tran_person_name,
                                                   tran_document_prefix,
                                                   tran_document_number,
                                                   tran_sign_verified,
                                                   system_posted_tran,
                                                   transaction_narration,
                                                   app_user_id,
                                                   app_data_time)
                 VALUES (p_branch_code,
                         p_center_code,
                         p_tran_date,
                         w_batch_serial,
                         w_account_number,
                         p_transaction_ledger,
                         w_contra_gl_code,
                         w_tran_debit_credit,
                         p_transaction_type,
                         w_tran_amount,
                         0.00,
                         NULL,
                         NULL,
                         NULL,
                         NULL,
                         FALSE,
                         FALSE,
                         p_tran_narration,
                         p_app_user_id,
                         current_timestamp);
         END IF;
      END LOOP;

      SELECT *
        INTO w_status, w_errm, w_batch_number
        FROM fn_finance_post_tran (p_branch_code,
                                   p_center_code,
                                   p_app_user_id,
                                   p_transaction_type,
                                   p_tran_date,
                                   p_tran_narration,
                                   p_tran_source);

      IF w_tran_gl_code = p_transaction_ledger
      THEN
         BEGIN
            SELECT COALESCE (max (batch_number) + 1, 1)
             INTO w_day_serial_no
             FROM finance_cash_transaction
            WHERE     branch_code = p_branch_code
                  AND app_user_id = p_app_user_id
                  AND transaction_date = p_tran_date;

            INSERT INTO finance_cash_transaction (branch_code,
                                                  center_code,
                                                  transaction_date,
                                                  batch_number,
                                                  day_serial_no,
                                                  receive_payment,
                                                  transaction_amount,
                                                  transaction_narration,
                                                  auth_by,
                                                  auth_on,
                                                  cancel_by,
                                                  cancel_on,
                                                  app_user_id,
                                                  app_data_time)
                 VALUES (p_branch_code,
                         p_center_code,
                         p_tran_date,
                         w_batch_number,
                         w_day_serial_no,
                         p_receive_payment,
                         w_tran_amount,
                         p_tran_narration,
                         p_app_user_id,
                         current_timestamp,
                         NULL,
                         NULL,
                         p_app_user_id,
                         current_timestamp);
         END;
      END IF;

      o_batch_number := w_batch_number;
      o_status := w_status;
      o_errm := w_errm;
   END IF;
END;
$$;


ALTER FUNCTION public.fn_finance_post_cash_tran(p_branch_code integer, p_center_code character, p_app_user_id character, p_transaction_type character, p_transaction_ledger character, p_tran_date date, p_tran_narration character, p_receive_payment character, p_tran_source character, OUT o_status character, OUT o_errm character, OUT o_batch_number character) OWNER TO postgres;

--
-- Name: fn_finance_post_tran(integer, character, character, character, date, character, character); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_finance_post_tran(p_branch_code integer, p_center_code character, p_app_user_id character, p_transaction_type character, p_tran_date date, p_tran_narration character, p_tran_source character, OUT o_status character, OUT o_errm character, OUT o_batch_number character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_error_message           VARCHAR;
   w_batch_number            INTEGER;
   w_check                   BOOLEAN;
   w_account_number          VARCHAR := '0';
   w_transaction_date        DATE;
   w_last_balance_update     DATE;
   w_last_transaction_date   DATE;
   w_last_monbal_update      DATE;
   TRAN_DATA                 RECORD;
   w_tran_gl_code            VARCHAR := '0';
   w_cash_transaction        BOOLEAN;
   w_total_leg               INTEGER;
   w_total_debit_amount      NUMERIC (22, 2) := 0;
   w_total_credit_amount     NUMERIC (22, 2) := 0;
   w_available_balance       NUMERIC (22, 2) := 0;
   w_new_credit_balance      NUMERIC (22, 2) := 0;
   w_new_debit_balance       NUMERIC (22, 2) := 0;
   w_new_available_balance   NUMERIC (22, 2) := 0;
   w_daily_credit_limit      NUMERIC (22, 2) := 0;
   w_daily_debit_limit       NUMERIC (22, 2) := 0;
   w_batch_serial            INTEGER := 0;
   w_status                  VARCHAR;
   w_errm                    VARCHAR;
   w_credit_limit            NUMERIC (22, 2) := 0;
   w_system_posted_tran      BOOL := FALSE;
   w_counter                 INTEGER := 0;
   w_branch_code             INTEGER := 0;
   w_cash_gl_code            VARCHAR;
   w_cash_user_id            VARCHAR;
BEGIN
   BEGIN
      SELECT COUNT (*)
        INTO w_total_leg
        FROM finance_transaction_table S
       WHERE S.app_user_id = p_app_user_id;
   END;

   IF w_total_leg = 0
   THEN
      w_status := 'E';
      w_errm := 'Nothing to Post.';
      RAISE EXCEPTION USING MESSAGE = w_errm;
   END IF;

   BEGIN
      SELECT COALESCE (max (batch_number) + 1, 1)
        INTO w_batch_number
        FROM finance_transaction_master
       WHERE branch_code = p_branch_code AND transaction_date = p_tran_date;
   END;

   BEGIN
      SELECT daily_credit_limit,
             daily_debit_limit,
             branch_code,
             cash_gl_code
        INTO w_daily_credit_limit,
             w_daily_debit_limit,
             w_branch_code,
             w_cash_gl_code
        FROM appauth_user_settings
       WHERE app_user_id = p_app_user_id;
   END;

   FOR TRAN_DATA
      IN (  SELECT branch_code,
                   center_code,
                   transaction_date,
                   batch_serial,
                   account_number,
                   tran_gl_code,
                   contra_gl_code,
                   tran_debit_credit,
                   tran_type,
                   tran_amount,
                   (CASE
                       WHEN tran_debit_credit = 'D' THEN -tran_amount
                       ELSE tran_amount
                    END) balance_amount,
                   (CASE
                       WHEN tran_debit_credit = 'D' THEN tran_amount
                       ELSE 0
                    END) debit_amount,
                   (CASE
                       WHEN tran_debit_credit = 'C' THEN tran_amount
                       ELSE 0
                    END) credit_amount,
                   available_balance,
                   tran_document_prefix,
                   tran_document_number,
                   tran_person_phone,
                   tran_person_name,
                   tran_sign_verified,
                   system_posted_tran,
                   transaction_narration,
                   app_user_id,
                   app_data_time
              FROM finance_transaction_table S
             WHERE S.app_user_id = p_app_user_id
          ORDER BY batch_serial)
   LOOP
      w_account_number := TRAN_DATA.account_number;
      w_transaction_date := TRAN_DATA.transaction_date;
      w_tran_gl_code := TRAN_DATA.tran_gl_code;
      w_total_debit_amount := w_total_debit_amount + TRAN_DATA.debit_amount;
      w_total_credit_amount :=
         w_total_credit_amount + TRAN_DATA.credit_amount;
      w_batch_serial := w_batch_serial + 1;

      w_last_balance_update := NULL;
      w_last_transaction_date := NULL;

      IF w_account_number != '0'
      THEN
         BEGIN
            SELECT account_ledger_code
              INTO STRICT w_tran_gl_code
              FROM finance_accounts_balance
             WHERE account_number = w_account_number;
         EXCEPTION
            WHEN NO_DATA_FOUND
            THEN
               RAISE EXCEPTION USING MESSAGE = 'Invalid Account Number!';
         END;
      END IF;

      IF     COALESCE (TRAN_DATA.account_number, '0') = '0'
         AND COALESCE (TRAN_DATA.tran_gl_code, '0') = '0'
      THEN
         RAISE EXCEPTION
         USING MESSAGE =
                  'Posting Error Both ledger code and phone number can not be Zero!';
      END IF;

      IF     TRAN_DATA.tran_debit_credit = 'D'
         AND TRAN_DATA.debit_amount > w_daily_debit_limit
      THEN
         RAISE EXCEPTION
         USING MESSAGE =
                     'Your Transaction Limit '
                  || w_daily_debit_limit
                  || ' Will be Exceeded for This Transaction!';
      END IF;

      IF     TRAN_DATA.tran_debit_credit = 'C'
         AND TRAN_DATA.credit_amount > w_daily_credit_limit
      THEN
         RAISE EXCEPTION
         USING MESSAGE =
                     'Your Transaction Limit '
                  || w_daily_credit_limit
                  || ' Will be Exceeded for This Transaction!';
      END IF;

      IF w_tran_gl_code != '0'
      THEN
         BEGIN
            SELECT gl_code
              INTO STRICT w_tran_gl_code
              FROM finance_general_ledger
             WHERE gl_code = w_tran_gl_code;
         EXCEPTION
            WHEN NO_DATA_FOUND
            THEN
               RAISE EXCEPTION
               USING MESSAGE =
                           'Posting Error Invalid Ledger Code! '
                        || w_tran_gl_code;
         END;

         BEGIN
            SELECT gl_balance,
                   COALESCE (last_balance_update, w_transaction_date)
                      last_balance_update,
                   COALESCE (last_transaction_date, w_transaction_date)
                      last_transaction_date,
                   COALESCE (last_monbal_update, w_transaction_date)
                      last_monbal_update
              INTO STRICT w_available_balance,
                          w_last_balance_update,
                          w_last_transaction_date,
                          w_last_monbal_update
              FROM finance_ledger_balance
             WHERE     branch_code = TRAN_DATA.branch_code
                   AND gl_code = w_tran_gl_code;

            w_last_balance_update :=
               LEAST (w_last_balance_update, w_transaction_date);
            w_last_transaction_date :=
               GREATEST (w_last_transaction_date, w_transaction_date);
            w_last_monbal_update :=
               LEAST (w_last_monbal_update, w_transaction_date);


            UPDATE finance_ledger_balance
               SET gl_balance = gl_balance + TRAN_DATA.balance_amount,
                   total_debit_sum = total_debit_sum + TRAN_DATA.debit_amount,
                   total_credit_sum =
                      total_credit_sum + TRAN_DATA.credit_amount,
                   last_balance_update = w_last_balance_update,
                   last_transaction_date = w_last_transaction_date,
                   last_monbal_update = w_last_monbal_update,
                   is_balance_updated = FALSE,
                   is_monbal_updated = FALSE,
                   is_monbal_recpay_updated = FALSE
             WHERE     branch_code = TRAN_DATA.branch_code
                   AND gl_code = w_tran_gl_code;

            UPDATE finance_cash_and_bank_ledger
               SET last_balance_update = w_last_balance_update,
                   last_transaction_date = w_last_transaction_date,
                   is_balance_updated = FALSE
             WHERE     branch_code = TRAN_DATA.branch_code
                   AND gl_code = w_tran_gl_code;

            w_available_balance :=
               w_available_balance + TRAN_DATA.balance_amount;
         EXCEPTION
            WHEN NO_DATA_FOUND
            THEN
               INSERT INTO finance_ledger_balance (branch_code,
                                                   gl_code,
                                                   last_transaction_date,
                                                   last_balance_update,
                                                   is_balance_updated,
                                                   is_monbal_updated,
                                                   is_monbal_recpay_updated,
                                                   total_debit_sum,
                                                   total_credit_sum,
                                                   gl_balance,
                                                   unauth_debit_sum,
                                                   unauth_credit_sum,
                                                   transfer_debit_sum,
                                                   transfer_credit_sum,
                                                   auth_by,
                                                   auth_on,
                                                   cancel_by,
                                                   cancel_on,
                                                   app_user_id,
                                                   app_data_time)
                    VALUES (TRAN_DATA.branch_code,
                            w_tran_gl_code,
                            w_transaction_date,
                            w_transaction_date,
                            FALSE,
                            FALSE,
                            FALSE,
                            TRAN_DATA.debit_amount,
                            TRAN_DATA.credit_amount,
                            TRAN_DATA.balance_amount,
                            0.00,
                            0.00,
                            0.00,
                            0.00,
                            NULL,
                            NULL,
                            NULL,
                            NULL,
                            p_app_user_id,
                            current_timestamp);

               w_available_balance := TRAN_DATA.balance_amount;
         END;
      END IF;

      IF TRAN_DATA.system_posted_tran
      THEN
         w_system_posted_tran := TRUE;
      END IF;

      IF w_account_number != '0'
      THEN
         BEGIN
            SELECT COALESCE (account_balance, 0),
                   COALESCE (credit_limit, 0),
                   COALESCE (last_balance_update, w_transaction_date)
                      last_balance_update,
                   COALESCE (last_transaction_date, w_transaction_date)
                      last_transaction_date,
                   COALESCE (last_monbal_update, w_transaction_date)
                      last_monbal_update
              INTO STRICT w_available_balance,
                          w_credit_limit,
                          w_last_balance_update,
                          w_last_transaction_date,
                          w_last_monbal_update
              FROM finance_accounts_balance
             WHERE account_number = w_account_number;
         EXCEPTION
            WHEN NO_DATA_FOUND
            THEN
               RAISE EXCEPTION
               USING MESSAGE = 'Invalid Account Number !' || w_account_number;
         END;

         w_last_transaction_date :=
            GREATEST (w_last_transaction_date, w_transaction_date);
         w_last_balance_update :=
            least (w_last_balance_update, w_transaction_date);
         w_last_monbal_update :=
            LEAST (w_last_monbal_update, w_transaction_date);

         UPDATE finance_accounts_balance
            SET account_balance = account_balance + TRAN_DATA.balance_amount,
                total_debit_amount =
                   total_debit_amount + TRAN_DATA.debit_amount,
                total_credit_amount =
                   total_credit_amount + TRAN_DATA.credit_amount,
                last_balance_update = w_last_balance_update,
                last_transaction_date = w_last_transaction_date,
                last_monbal_update = w_last_monbal_update,
                is_balance_updated = FALSE
          WHERE account_number = w_account_number;

         BEGIN
            SELECT sum (tran_amount)
             INTO w_new_credit_balance
             FROM finance_transaction_table S
            WHERE     S.branch_code = p_branch_code
                  AND S.app_user_id = p_app_user_id
                  AND s.account_number = w_account_number
                  AND s.tran_debit_credit = 'C';
         END;

         BEGIN
            SELECT sum (tran_amount)
             INTO w_new_debit_balance
             FROM finance_transaction_table S
            WHERE     S.branch_code = p_branch_code
                  AND S.app_user_id = p_app_user_id
                  AND s.account_number = w_account_number
                  AND s.tran_debit_credit = 'D';
         END;

         w_new_available_balance :=
            w_new_credit_balance - w_new_debit_balance;

         -- w_errm:= w_available_balance||' . '||TRAN_DATA.tran_amount||TRAN_DATA.tran_debit_credit||' . '||w_credit_limit;
         -- w_status := 'E';
         -- RAISE EXCEPTION USING MESSAGE = w_errm;

         IF     TRAN_DATA.tran_debit_credit = 'D'
            AND (w_available_balance) < TRAN_DATA.tran_amount
         THEN
            IF    w_credit_limit < abs (w_available_balance)
               OR w_credit_limit = 0
            THEN
               w_status := 'E';
               w_errm :=
                     'Credit Limit ('
                  || w_available_balance
                  || ') Exceed For This Transaction!';
               RAISE EXCEPTION USING MESSAGE = w_errm;
            END IF;
         END IF;
      END IF;


      IF w_cash_gl_code = w_tran_gl_code
      THEN
         BEGIN
            SELECT teller_id
              INTO STRICT w_cash_user_id
              FROM finance_transaction_telbal
             WHERE teller_id = p_app_user_id;

            UPDATE finance_transaction_telbal
               SET total_credit_amount =
                      total_credit_amount + TRAN_DATA.credit_amount,
                   total_debit_amount =
                      total_debit_amount + TRAN_DATA.debit_amount,
                   cash_balance = cash_balance + TRAN_DATA.balance_amount
             WHERE teller_id = p_app_user_id;
         EXCEPTION
            WHEN NO_DATA_FOUND
            THEN
               INSERT INTO finance_transaction_telbal (branch_code,
                                                       teller_id,
                                                       cash_od_allowed,
                                                       credit_limit_amount,
                                                       debit_limit_amount,
                                                       total_credit_amount,
                                                       total_debit_amount,
                                                       cash_balance,
                                                       app_user_id,
                                                       app_data_time)
                    VALUES (p_branch_code,
                            p_app_user_id,
                            FALSE,
                            999999999999999.00,
                            999999999999999.00,
                            TRAN_DATA.credit_amount,
                            TRAN_DATA.debit_amount,
                            TRAN_DATA.balance_amount,
                            p_app_user_id,
                            current_timestamp);
         END;
      END IF;

      INSERT INTO finance_transaction_details (branch_code,
                                               center_code,
                                               transaction_date,
                                               batch_number,
                                               batch_serial,
                                               account_number,
                                               tran_gl_code,
                                               contra_gl_code,
                                               tran_debit_credit,
                                               tran_type,
                                               tran_amount,
                                               cancel_amount,
                                               available_balance,
                                               tran_document_prefix,
                                               tran_document_number,
                                               tran_person_phone,
                                               tran_person_name,
                                               tran_sign_verified,
                                               system_posted_tran,
                                               transaction_narration,
                                               auth_by,
                                               auth_on,
                                               cancel_by,
                                               cancel_on,
                                               app_user_id,
                                               app_data_time)
           VALUES (p_branch_code,
                   TRAN_DATA.center_code,
                   p_tran_date,
                   w_batch_number,
                   w_batch_serial,
                   w_account_number,
                   w_tran_gl_code,
                   TRAN_DATA.contra_gl_code,
                   TRAN_DATA.tran_debit_credit,
                   TRAN_DATA.tran_type,
                   TRAN_DATA.tran_amount,
                   0,
                   w_available_balance,
                   TRAN_DATA.tran_document_prefix,
                   TRAN_DATA.tran_document_number,
                   TRAN_DATA.tran_person_phone,
                   TRAN_DATA.tran_person_name,
                   TRAN_DATA.tran_sign_verified,
                   TRAN_DATA.system_posted_tran,
                   TRAN_DATA.transaction_narration,
                   p_app_user_id,
                   current_timestamp,
                   NULL,
                   NULL,
                   p_app_user_id,
                   current_timestamp);
   /*
         IF w_account_number != '0'
         THEN
            SELECT w_status, w_errm
              INTO w_status, w_errm
              FROM fn_finance_acbal_hist (w_account_number,
                                          w_last_transaction_date);

            IF w_status = 'E'
            THEN
               RAISE EXCEPTION USING MESSAGE = w_errm;
            END IF;
         END IF;

         IF w_tran_gl_code != '0'
         THEN
            SELECT w_status, w_errm
              INTO w_status, w_errm
              FROM fn_finance_glbal_hist (w_tran_gl_code,
                                          p_branch_code,
                                          w_last_transaction_date);

            IF w_status = 'E'
            THEN
               RAISE EXCEPTION USING MESSAGE = w_errm;
            END IF;

            SELECT w_status, w_errm
              INTO w_status, w_errm
              FROM fn_finance_glmonbal_hist (w_tran_gl_code,
                                             p_branch_code,
                                             w_last_transaction_date);

            IF w_status = 'E'
            THEN
               RAISE EXCEPTION USING MESSAGE = w_errm;
            END IF;
         END IF;
         */
   END LOOP;

   IF w_total_debit_amount != w_total_credit_amount
   THEN
      w_status := 'E';
      w_errm :=
            'Total Debit ('
         || w_total_debit_amount
         || ') and Credit Amount ('
         || w_total_credit_amount
         || ') Must Be Same';
      RAISE EXCEPTION USING MESSAGE = w_errm;
   END IF;

   BEGIN
      INSERT INTO finance_transaction_master (branch_code,
                                              center_code,
                                              transaction_date,
                                              batch_number,
                                              tran_type,
                                              total_debit_amount,
                                              total_credit_amount,
                                              tran_source_table,
                                              tran_source_key,
                                              transaction_narration,
                                              system_posted_tran,
                                              auth_by,
                                              auth_on,
                                              cancel_by,
                                              cancel_on,
                                              app_user_id,
                                              app_data_time)
           VALUES (p_branch_code,
                   p_center_code,
                   p_tran_date,
                   w_batch_number,
                   p_transaction_type,
                   w_total_debit_amount,
                   w_total_credit_amount,
                   p_tran_source,
                   'NA',
                   p_tran_narration,
                   w_system_posted_tran,
                   p_app_user_id,
                   current_timestamp,
                   NULL,
                   NULL,
                   p_app_user_id,
                   current_timestamp);
   END;

   BEGIN
      DELETE FROM finance_transaction_table S
            WHERE S.app_user_id = p_app_user_id;
   END;

   o_batch_number := w_batch_number;
   o_status := 'S';
   o_errm := '';
EXCEPTION
   WHEN OTHERS
   THEN
      IF w_status = 'E'
      THEN
         o_status := w_status;
         o_errm := w_errm;
         o_batch_number := 0;
      ELSE
         o_errm := SQLERRM;
         o_status := 'E';
         o_batch_number := 0;
      END IF;
END;
$$;


ALTER FUNCTION public.fn_finance_post_tran(p_branch_code integer, p_center_code character, p_app_user_id character, p_transaction_type character, p_tran_date date, p_tran_narration character, p_tran_source character, OUT o_status character, OUT o_errm character, OUT o_batch_number character) OWNER TO postgres;

--
-- Name: fn_finance_post_tran_cancel(integer, character, date, integer, character); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_finance_post_tran_cancel(p_branch_code integer, p_app_user_id character, p_tran_date date, p_batch_number integer, p_cancel_reason character, OUT o_status character, OUT o_errm character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_error_message           VARCHAR;
   w_status                  VARCHAR;
   w_batch_number            INTEGER;
   w_check                   BOOLEAN;
   w_account_number          VARCHAR := '0';
   w_transaction_date        DATE;
   w_last_balance_update     DATE;
   w_last_transaction_date   DATE;
   w_last_monbal_update      DATE;
   TRAN_DATA                 RECORD;
   w_tran_gl_code            VARCHAR := '0';
   w_cash_transaction        BOOLEAN;
   w_total_leg               INTEGER;
   w_total_debit_amount      NUMERIC (22, 2) := 0;
   w_total_credit_amount     NUMERIC (22, 2) := 0;
   w_available_balance       NUMERIC (22, 2) := 0;
   w_batch_serial            INTEGER := 0;
   w_counter                 INTEGER := 0;
BEGIN
   BEGIN
      SELECT count (1)
       INTO w_counter
       FROM finance_transaction_details S
      WHERE     S.branch_code = p_branch_code
            AND s.transaction_date = p_tran_date
            AND s.batch_number = p_batch_number;
   END;

   IF w_counter = 0
   THEN
      RAISE EXCEPTION USING MESSAGE = 'Invalid Batch Information';
   END IF;

   w_counter := 0;

   FOR TRAN_DATA
      IN (  SELECT branch_code,
                   transaction_date,
                   batch_serial,
                   account_number,
                   tran_gl_code,
                   contra_gl_code,
                   tran_debit_credit,
                   tran_type,
                   tran_amount,
                   (CASE
                       WHEN tran_debit_credit = 'C' THEN -tran_amount
                       ELSE tran_amount
                    END) balance_amount,
                   (CASE
                       WHEN tran_debit_credit = 'D' THEN -tran_amount
                       ELSE 0
                    END) debit_amount,
                   (CASE
                       WHEN tran_debit_credit = 'C' THEN -tran_amount
                       ELSE 0
                    END) credit_amount,
                   available_balance,
                   tran_document_prefix,
                   tran_document_number,
                   tran_person_phone,
                   tran_person_name,
                   tran_sign_verified,
                   system_posted_tran,
                   transaction_narration,
                   app_user_id,
                   app_data_time
              FROM finance_transaction_details S
             WHERE     S.branch_code = p_branch_code
                   AND s.transaction_date = p_tran_date
                   AND s.batch_number = p_batch_number
                   AND s.cancel_by IS NULL
          ORDER BY batch_serial)
   LOOP
      w_account_number := TRAN_DATA.account_number;
      w_transaction_date := TRAN_DATA.transaction_date;
      w_tran_gl_code := TRAN_DATA.tran_gl_code;
      w_total_debit_amount := w_total_debit_amount + TRAN_DATA.debit_amount;
      w_total_credit_amount :=
         w_total_credit_amount + TRAN_DATA.credit_amount;
      w_batch_serial := w_batch_serial + 1;
      w_counter := w_counter + 1;

      IF w_tran_gl_code != '0'
      THEN
         BEGIN
            SELECT gl_balance,
                   COALESCE (last_balance_update, w_transaction_date)
                      last_balance_update,
                   COALESCE (last_transaction_date, w_transaction_date)
                      last_transaction_date,
                   COALESCE (last_monbal_update, w_transaction_date)
                      last_monbal_update
              INTO STRICT w_available_balance,
                          w_last_balance_update,
                          w_last_transaction_date,
                          w_last_monbal_update
              FROM finance_ledger_balance
             WHERE     branch_code = TRAN_DATA.branch_code
                   AND gl_code = w_tran_gl_code;

            w_last_balance_update :=
               LEAST (w_last_balance_update, w_transaction_date);
            w_last_transaction_date :=
               GREATEST (w_last_transaction_date, w_transaction_date);
            w_last_monbal_update :=
               LEAST (w_last_monbal_update, w_transaction_date);

            UPDATE finance_ledger_balance
               SET gl_balance = gl_balance + TRAN_DATA.balance_amount,
                   total_debit_sum = total_debit_sum + TRAN_DATA.debit_amount,
                   total_credit_sum =
                      total_credit_sum + TRAN_DATA.credit_amount,
                   last_balance_update = w_last_balance_update,
                   last_transaction_date = w_last_transaction_date,
                   last_monbal_update = w_last_monbal_update,
                   is_balance_updated = FALSE,
                   is_monbal_updated = FALSE,
                   is_monbal_recpay_updated = FALSE
             WHERE     branch_code = TRAN_DATA.branch_code
                   AND gl_code = w_tran_gl_code;

            UPDATE finance_cash_and_bank_ledger
               SET last_balance_update = w_last_balance_update,
                   last_transaction_date = w_last_transaction_date,
                   is_balance_updated = FALSE
             WHERE     branch_code = TRAN_DATA.branch_code
                   AND gl_code = w_tran_gl_code;

            DELETE FROM finance_ledger_balance_hist
                  WHERE     gl_code = w_tran_gl_code
                        AND transaction_date = w_transaction_date
                        AND branch_code = TRAN_DATA.branch_code;

            DELETE FROM finance_led_rec_pay_bal_hist
                  WHERE     gl_code = TRAN_DATA.contra_gl_code
                        AND transaction_date = w_transaction_date
                        AND branch_code = TRAN_DATA.branch_code;
         END;
      END IF;

      IF w_account_number != '0'
      THEN
         BEGIN
            SELECT COALESCE (account_balance, 0),
                   COALESCE (last_balance_update, w_transaction_date)
                      last_balance_update,
                   COALESCE (last_transaction_date, w_transaction_date)
                      last_transaction_date,
                   COALESCE (last_monbal_update, w_transaction_date)
                      last_monbal_update
              INTO STRICT w_available_balance,
                          w_last_balance_update,
                          w_last_transaction_date,
                          w_last_monbal_update
              FROM finance_accounts_balance
             WHERE account_number = w_account_number;
         EXCEPTION
            WHEN NO_DATA_FOUND
            THEN
               RAISE EXCEPTION
               USING MESSAGE = 'Invalid Account Number !' || w_account_number;
         END;

         w_last_transaction_date :=
            GREATEST (w_last_transaction_date, w_transaction_date);
         w_last_balance_update :=
            least (w_last_balance_update, w_transaction_date);
         w_last_monbal_update :=
            LEAST (w_last_monbal_update, w_transaction_date);

         UPDATE finance_accounts_balance
            SET account_balance = account_balance + TRAN_DATA.balance_amount,
                total_debit_amount =
                   total_debit_amount + TRAN_DATA.debit_amount,
                total_credit_amount =
                   total_credit_amount + TRAN_DATA.credit_amount,
                last_balance_update = w_last_balance_update,
                last_transaction_date = w_last_transaction_date,
                last_monbal_update = w_last_monbal_update,
                is_balance_updated = FALSE
          WHERE account_number = w_account_number;

         DELETE FROM finance_accounts_balance_hist
               WHERE     account_number = w_account_number
                     AND transaction_date = w_transaction_date;
      END IF;

      BEGIN
         UPDATE finance_transaction_details S
            SET cancel_amount = tran_amount,
                cancel_by = p_app_user_id,
                cancel_on = current_timestamp,
                cancel_remarks = p_cancel_reason
          WHERE     S.branch_code = p_branch_code
                AND s.transaction_date = p_tran_date
                AND s.batch_number = p_batch_number;

         UPDATE finance_transaction_master M
            SET cancel_by = p_app_user_id,
                cancel_on = current_timestamp,
                cancel_remarks = p_cancel_reason
          WHERE     M.branch_code = p_branch_code
                AND M.transaction_date = p_tran_date
                AND M.batch_number = p_batch_number;

         UPDATE finance_cash_transaction M
            SET cancel_by = p_app_user_id,
                cancel_on = current_timestamp,
                cancel_remarks = p_cancel_reason
          WHERE     M.branch_code = p_branch_code
                AND M.transaction_date = p_tran_date
                AND M.batch_number = p_batch_number;
      END;
   END LOOP;

   IF w_counter = 0
   THEN
      RAISE EXCEPTION USING MESSAGE = 'Batch Already Canceled!';
   END IF;

   o_status := 'S';
   o_errm := '';
EXCEPTION
   WHEN OTHERS
   THEN
      IF w_status = 'E'
      THEN
         o_status := w_status;
         o_errm := w_error_message;
      ELSE
         o_errm := SQLERRM;
         o_status := 'E';
      END IF;
END;
$$;


ALTER FUNCTION public.fn_finance_post_tran_cancel(p_branch_code integer, p_app_user_id character, p_tran_date date, p_batch_number integer, p_cancel_reason character, OUT o_status character, OUT o_errm character) OWNER TO postgres;

--
-- Name: fn_finance_query_account_statement(character, date, date, character); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_finance_query_account_statement(p_account_number character, p_from_date date, p_upto_date date, p_app_user_id character, OUT o_status character, OUT o_errm character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_status                  VARCHAR;
   w_counter                 INTEGER;
   w_errm                    VARCHAR;
   w_last_transaction_date   DATE;
   w_account_number          VARCHAR;
   w_account_title           VARCHAR;
   w_account_balance         NUMERIC (22, 2) := 0;
BEGIN
   SELECT count (account_number)
     INTO w_counter
     FROM finance_accounts_balance
    WHERE account_number = p_account_number;

   IF w_counter = 0
   THEN
      RAISE EXCEPTION USING MESSAGE = 'Invalid Account Number!';
   END IF;

   SELECT account_number,
          account_title,
          account_balance,
          last_transaction_date
     INTO w_account_number,
          w_account_title,
          w_account_balance,
          w_last_transaction_date
     FROM finance_accounts_balance
    WHERE account_number = p_account_number;

   SELECT w_status, w_errm
     INTO w_status, w_errm
     FROM fn_finance_acbal_hist (p_account_number, w_last_transaction_date);

   DELETE FROM appauth_query_table
         WHERE app_user_id = p_app_user_id;

   INSERT INTO appauth_query_table (chr_column1,
                                    chr_column3,
                                    chr_column4,
                                    dec_column4,
                                    dat_column1,
                                    chr_column2,
                                    dec_column1,
                                    dec_column2,
                                    dec_column3,
                                    app_user_id)
      SELECT serial_number,
             w_account_number,
             w_account_title,
             w_account_balance,
             transaction_date,
             transaction_narration,
             credit_balance,
             debit_balance,
             SUM (credit_balance - debit_balance)
                OVER (ORDER BY serial_number) account_balance,
             p_app_user_id
        FROM (SELECT 1  serial_number,
                     p_from_date - 1 transaction_date,
                     'Opening Balance' transaction_narration,
                     (CASE
                         WHEN o_account_balance > 0 THEN o_account_balance
                         ELSE 0
                      END) credit_balance,
                     (CASE
                         WHEN o_account_balance < 0
                         THEN
                            abs (o_account_balance)
                         ELSE
                            0
                      END) debit_balance
                FROM fn_finance_get_ason_acbal (p_account_number,
                                                p_from_date - 1)
              UNION ALL
              SELECT   (ROW_NUMBER ()
                        OVER (
                           ORDER BY
                              transaction_date, batch_number, batch_serial))
                     + 1 serial_number,
                     transaction_date,
                     transaction_narration,
                     (CASE
                         WHEN tran_debit_credit = 'C' THEN tran_amount
                         ELSE 0
                      END) credit_balance,
                     (CASE
                         WHEN tran_debit_credit = 'D' THEN tran_amount
                         ELSE 0
                      END) debit_balance
                FROM finance_transaction_details
               WHERE     account_number = p_account_number
                     AND cancel_by IS NULL
                     AND transaction_date BETWEEN p_from_date AND p_upto_date)
             a;

   o_status := 'S';
   o_errm := '';
EXCEPTION
   WHEN OTHERS
   THEN
      IF w_status = 'E'
      THEN
         o_status := w_status;
         o_errm := w_errm;
      ELSE
         o_errm := SQLERRM;
         o_status := 'E';
      END IF;
END;
$$;


ALTER FUNCTION public.fn_finance_query_account_statement(p_account_number character, p_from_date date, p_upto_date date, p_app_user_id character, OUT o_status character, OUT o_errm character) OWNER TO postgres;

--
-- Name: fn_finance_query_daily_transaction(integer, date, date, character, character, character); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_finance_query_daily_transaction(p_branch_code integer, p_from_date date, p_upto_date date, p_account_number character, p_tran_gl_code character, p_app_user_id character, OUT o_status character, OUT o_errm character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_errm        VARCHAR;
   w_status      VARCHAR;
   w_sql_stat    TEXT := '';
   w_ason_date   DATE;
   w_from_date   DATE;
   w_upto_date   DATE;
BEGIN
   IF p_from_date = p_upto_date
   THEN
      w_ason_date := p_from_date;
   ELSE
      w_from_date := p_from_date;
      w_upto_date := p_upto_date;
   END IF;

   DELETE FROM appauth_query_table
         WHERE app_user_id = p_app_user_id;

   IF p_account_number <> '0'
   THEN
      w_sql_stat :=
            'INSERT INTO appauth_query_table (int_column1,
                                  dat_column1,
                                  int_column2,
                                  chr_column1,
                                  chr_column2,
                                  chr_column3,
                                  chr_column4,
                                  chr_column5,
                                  dec_column1,
                                  dec_column2,
                                  chr_column6,
                                  chr_column7,
                                  chr_column8,
                                  dat_column2,
                                  chr_column9,
                                  dat_column3,
                                  app_user_id)
      SELECT t.branch_code,
             t.transaction_date,
             t.batch_number,
             t.tran_gl_code,
             l.gl_name,
             t.account_number,
             a.account_title account_name,
             (case when t.tran_debit_credit=''C'' then ''Payment'' else ''Receipt'' end) tran_debit_credit,
             t.tran_amount,
             t.cancel_amount,
             t.tran_document_number,
             t.transaction_narration,
             t.cancel_by,
             t.cancel_on,
             t.app_user_id,
             t.app_data_time,
             '''
         || p_app_user_id
         || '''
        FROM finance_transaction_details t, finance_general_ledger l, finance_accounts_balance a
       WHERE t.tran_gl_code = l.gl_code 
       and a.account_number=t.account_number
       and a.account_number= '''
         || p_account_number
         || '''';
   ELSIF p_tran_gl_code <> '0'
   THEN
      w_sql_stat :=
            'INSERT INTO appauth_query_table (int_column1,
                                  dat_column1,
                                  int_column2,
                                  chr_column1,
                                  chr_column2,
                                  chr_column3,
                                  chr_column4,
                                  chr_column5,
                                  dec_column1,
                                  dec_column2,
                                  chr_column6,
                                  chr_column7,
                                  chr_column8,
                                  dat_column2,
                                  chr_column9,
                                  dat_column3,
                                  app_user_id)
      SELECT t.branch_code,
             t.transaction_date,
             t.batch_number,
             t.tran_gl_code,
             l.gl_name,
             t.account_number,
             '' '' account_name,
             (case when t.tran_debit_credit=''C'' then ''Payment'' else ''Receipt'' end) tran_debit_credit,
             t.tran_amount,
             t.cancel_amount,
             t.tran_document_number,
             t.transaction_narration,
             t.cancel_by,
             t.cancel_on,
             t.app_user_id,
             t.app_data_time,
             '''
         || p_app_user_id
         || '''
        FROM finance_transaction_details t, finance_general_ledger l
       WHERE t.tran_gl_code = l.gl_code ';
   END IF;



   IF p_account_number <> '0' OR p_tran_gl_code <> '0'
   THEN
      IF p_tran_gl_code <> '0'
      THEN
         w_sql_stat :=
               w_sql_stat
            || ' and t.tran_gl_code = '''
            || p_tran_gl_code
            || '''';
      END IF;

      IF w_from_date IS NOT NULL AND w_upto_date IS NOT NULL
      THEN
         w_sql_stat :=
               w_sql_stat
            || ' and t.transaction_date between '''
            || w_from_date
            || ''' and '''
            || w_upto_date
            || '''';
      END IF;

      IF w_ason_date IS NOT NULL
      THEN
         w_sql_stat :=
               w_sql_stat
            || ' and t.transaction_date = '''
            || w_ason_date
            || '''';
      END IF;

      IF p_branch_code IS NOT NULL
      THEN
         w_sql_stat := w_sql_stat || ' and t.branch_code = ' || p_branch_code;
      END IF;


      --RAISE EXCEPTION USING MESSAGE = w_sql_stat;

      EXECUTE w_sql_stat;
   END IF;

   o_status := 'S';
   o_errm := '';
EXCEPTION
   WHEN OTHERS
   THEN
      IF w_status = 'E'
      THEN
         o_status := w_status;
         o_errm := w_errm;
      ELSE
         o_errm := SQLERRM;
         o_status := 'E';
      END IF;
END;
$$;


ALTER FUNCTION public.fn_finance_query_daily_transaction(p_branch_code integer, p_from_date date, p_upto_date date, p_account_number character, p_tran_gl_code character, p_app_user_id character, OUT o_status character, OUT o_errm character) OWNER TO postgres;

--
-- Name: fn_finance_query_document_number(character, character); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_finance_query_document_number(p_memo_number character, p_app_user_id character, OUT o_status character, OUT o_errm character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_errm     VARCHAR;
   w_status   VARCHAR;
BEGIN
   DELETE FROM sales_query_table
         WHERE app_user_id = p_app_user_id;

   INSERT INTO sales_query_table (chr_column1,
                                  chr_column2,
                                  dat_column1,
                                  dec_column1,
                                  chr_column3,
                                  chr_column4,
                                  app_user_id)
      SELECT center_code,
             client_id,
             tran_date,
             tran_amount,
             memo_num,
             tran_narration,
             p_app_user_id
        FROM (SELECT center_code,
                     client_id,
                     dpsrcv_date tran_date,
                     dpsrcv_amount tran_amount,
                     dpsrcv_memo_num memo_num,
                     dpsrcv_narration tran_narration
                FROM sales_dps_receive
               WHERE dpsrcv_memo_num = p_memo_number
              UNION ALL
              SELECT center_code,
                     client_id,
                     deposit_date tran_date,
                     deposit_amount tran_amount,
                     deposit_memo_num memo_num,
                     narration tran_narration
                FROM sales_deprcv_model
               WHERE deposit_memo_num = p_memo_number
              UNION ALL
              SELECT center_code,
                     client_id,
                     fee_collection_date tran_date,
                     fee_amount tran_amount,
                     fee_memo_number memo_num,
                     transaction_naration tran_narration
                FROM sales_fees_history
               WHERE fee_memo_number = p_memo_number
              UNION ALL
              SELECT center_code,
                     client_id,
                     instrcv_entry_date tran_date,
                     instrcv_instlmnt tran_amount,
                     instrcv_ref_num memo_num,
                     transaction_naration tran_narration
                FROM sales_emircv_model
               WHERE instrcv_ref_num = p_memo_number) t;

   o_status := 'S';
   o_errm := '';
EXCEPTION
   WHEN OTHERS
   THEN
      IF w_status = 'E'
      THEN
         o_status := w_status;
         o_errm := w_errm;
      ELSE
         o_errm := SQLERRM;
         o_status := 'E';
      END IF;
END;
$$;


ALTER FUNCTION public.fn_finance_query_document_number(p_memo_number character, p_app_user_id character, OUT o_status character, OUT o_errm character) OWNER TO postgres;

--
-- Name: fn_finance_query_ledger_statement(character, integer, date, date, character); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_finance_query_ledger_statement(p_gl_code character, p_branch_code integer, p_from_date date, p_upto_date date, p_app_user_id character, OUT o_status character, OUT o_errm character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_status                 VARCHAR;
   w_counter                INTEGER;
   w_errm                   VARCHAR;
   w_gl_name                VARCHAR;
   w_current_business_day   DATE;
   w_gl_balance             NUMERIC (20, 2);
BEGIN
   SELECT count (gl_code)
     INTO w_counter
     FROM finance_general_ledger
    WHERE gl_code = p_gl_code;

   DELETE FROM appauth_query_table
         WHERE app_user_id = p_app_user_id;

   IF w_counter = 0
   THEN
      RAISE EXCEPTION USING MESSAGE = 'Invalid Ledger Code!';
   END IF;

   --    RAISE EXCEPTION USING MESSAGE = p_branch_code;

   SELECT gl_name
     INTO w_gl_name
     FROM finance_general_ledger
    WHERE gl_code = p_gl_code;

   IF p_branch_code = 0
   THEN
      INSERT INTO appauth_query_table (chr_column1,
                                       dat_column1,
                                       chr_column2,
                                       dec_column1,
                                       dec_column2,
                                       dec_column3,
                                       app_user_id)
           SELECT serial_number,
                  transaction_date,
                  transaction_narration,
                  credit_balance,
                  debit_balance,
                  SUM (credit_balance - debit_balance)
                     OVER (ORDER BY serial_number) ledger_balance,
                  p_app_user_id
             FROM (SELECT 1  serial_number,
                          p_from_date - 1 transaction_date,
                          'Opening Balance' transaction_narration,
                          (CASE
                              WHEN o_gl_balance > 0 THEN o_gl_balance
                              ELSE 0
                           END) credit_balance,
                          (CASE
                              WHEN o_gl_balance < 0 THEN abs (o_gl_balance)
                              ELSE 0
                           END) debit_balance
                     FROM fn_finance_get_ason_glbal (p_branch_code,
                                                     p_gl_code,
                                                     p_from_date - 1)
                   UNION ALL
                   SELECT   (ROW_NUMBER ()
                             OVER (
                                ORDER BY
                                   transaction_date, batch_number, batch_serial))
                          + 1 serial_number,
                          transaction_date,
                          transaction_narration,
                          (CASE
                              WHEN tran_debit_credit = 'C' THEN tran_amount
                              ELSE 0
                           END) credit_balance,
                          (CASE
                              WHEN tran_debit_credit = 'D' THEN tran_amount
                              ELSE 0
                           END) debit_balance
                     FROM finance_transaction_details
                    WHERE     tran_gl_code = p_gl_code
                          AND transaction_date BETWEEN p_from_date
                                                   AND p_upto_date) a
         ORDER BY serial_number;

      SELECT sum (gl_balance)
        INTO w_gl_balance
        FROM finance_ledger_balance
       WHERE gl_code = p_gl_code;

      UPDATE appauth_query_table
         SET chr_column3 = w_gl_name, dec_column4 = w_gl_balance
       WHERE app_user_id = p_app_user_id;
   ELSIF p_branch_code > 0
   THEN
      INSERT INTO appauth_query_table (chr_column1,
                                       dat_column1,
                                       chr_column2,
                                       dec_column1,
                                       dec_column2,
                                       dec_column3,
                                       app_user_id)
           SELECT serial_number,
                  transaction_date,
                  transaction_narration,
                  credit_balance,
                  debit_balance,
                  SUM (credit_balance - debit_balance)
                     OVER (ORDER BY serial_number) ledger_balance,
                  p_app_user_id
             FROM (SELECT 1  serial_number,
                          p_from_date - 1 transaction_date,
                          'Opening Balance' transaction_narration,
                          (CASE
                              WHEN o_gl_balance > 0 THEN o_gl_balance
                              ELSE 0
                           END) credit_balance,
                          (CASE
                              WHEN o_gl_balance < 0 THEN abs (o_gl_balance)
                              ELSE 0
                           END) debit_balance
                     FROM fn_finance_get_ason_glbal (p_branch_code,
                                                     p_gl_code,
                                                     p_from_date - 1)
                   UNION ALL
                   SELECT   (ROW_NUMBER ()
                             OVER (
                                ORDER BY
                                   transaction_date, batch_number, batch_serial))
                          + 1 serial_number,
                          transaction_date,
                          transaction_narration,
                          (CASE
                              WHEN tran_debit_credit = 'C' THEN tran_amount
                              ELSE 0
                           END) credit_balance,
                          (CASE
                              WHEN tran_debit_credit = 'D' THEN tran_amount
                              ELSE 0
                           END) debit_balance
                     FROM finance_transaction_details
                    WHERE     tran_gl_code = p_gl_code
                          AND branch_code = p_branch_code
                          AND cancel_by IS NULL
                          AND transaction_date BETWEEN p_from_date
                                                   AND p_upto_date) a
         ORDER BY serial_number;

      SELECT sum (gl_balance)
        INTO w_gl_balance
        FROM finance_ledger_balance
       WHERE branch_code = p_branch_code AND gl_code = p_gl_code;

      UPDATE appauth_query_table
         SET chr_column3 = w_gl_name, dec_column4 = w_gl_balance
       WHERE app_user_id = p_app_user_id;
   END IF;

   o_status := 'S';
   o_errm := '';
EXCEPTION
   WHEN OTHERS
   THEN
      IF w_status = 'E'
      THEN
         o_status := w_status;
         o_errm := w_errm;
      ELSE
         o_errm := SQLERRM;
         o_status := 'E';
      END IF;
END;
$$;


ALTER FUNCTION public.fn_finance_query_ledger_statement(p_gl_code character, p_branch_code integer, p_from_date date, p_upto_date date, p_app_user_id character, OUT o_status character, OUT o_errm character) OWNER TO postgres;

--
-- Name: fn_get_inventory_number(integer, integer, character, character, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_get_inventory_number(p_inv_code integer, p_branch_code integer, p_inv_prefix character, p_inv_naration character, p_length integer DEFAULT 1) RETURNS character varying
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_message              VARCHAR;
   w_last_used_number     INTEGER;
   w_return               VARCHAR;
   w_inv_prefix           VARCHAR;
   w_number_with_prefix   VARCHAR;
   w_inv_length           INTEGER;
BEGIN
   BEGIN
      SELECT last_used_number, inv_prefix, inv_length
        INTO w_last_used_number, w_inv_prefix, w_inv_length
        FROM appauth_inventory_number s
       WHERE s.inv_code = p_inv_code AND s.branch_code = p_branch_code;

      IF NOT FOUND
      THEN
         INSERT INTO appauth_inventory_number (inv_code,
                                               branch_code,
                                               app_user_id,
                                               inv_prefix,
                                               last_used_number,
                                               inv_naration,
                                               inv_length)
              VALUES (p_inv_code,
                      p_branch_code,
                      NULL,
                      P_inv_prefix,
                      1,
                      p_inv_naration,
                      p_length);

         w_last_used_number := 1;
         w_inv_prefix := P_inv_prefix;
         w_inv_length := p_length;
      END IF;
   EXCEPTION
      WHEN NO_DATA_FOUND
      THEN
         INSERT INTO appauth_inventory_number (inv_code,
                                               branch_code,
                                               app_user_id,
                                               inv_prefix,
                                               last_used_number,
                                               inv_naration,
                                               inv_length)
              VALUES (p_inv_code,
                      p_branch_code,
                      NULL,
                      P_inv_prefix,
                      0,
                      p_inv_naration,
                      p_length);

         w_last_used_number := 1;
         w_inv_prefix := P_inv_prefix;
         w_inv_length := p_length;
   END;

   -- limit 100 for update;

   UPDATE appauth_inventory_number s
      SET last_used_number = last_used_number + 1
    WHERE s.inv_code = p_inv_code AND s.branch_code = p_branch_code;

   IF w_inv_length > 1
   THEN
      w_number_with_prefix :=
            w_inv_prefix
         || lpad (cast (w_last_used_number AS VARCHAR), w_inv_length, '0');
      w_return := w_number_with_prefix;
   ELSE
      w_return := w_inv_prefix || w_last_used_number;
   END IF;

   RETURN w_return;
END;
$$;


ALTER FUNCTION public.fn_get_inventory_number(p_inv_code integer, p_branch_code integer, p_inv_prefix character, p_inv_naration character, p_length integer) OWNER TO postgres;

--
-- Name: fn_get_next_installment_date(character, date, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_get_next_installment_date(p_inst_freq character, p_inst_from_date date, p_ason_date date) RETURNS date
    LANGUAGE plpgsql
    AS $$
DECLARE
   W_MESSAGE          CHARACTER (20);
   w_next_inst_date   DATE;
   O_ERRM             CHARACTER (100);
   W_STATUS           CHARACTER (20);
   W_NOI              INTEGER;
   W_NOD              INTEGER;
BEGIN
   IF p_inst_freq = 'W'
   THEN
      W_NOD := FLOOR ((p_ason_date - p_inst_from_date) / 7) * 7 + 7;
      w_next_inst_date := p_inst_from_date + W_NOD;
      W_NOI := W_NOD / 7;
   ELSIF p_inst_freq = 'M'
   THEN
      W_NOI := DATE_PART ('month', AGE (p_ason_date, p_inst_from_date)) + 1;
      w_next_inst_date :=
         (p_inst_from_date + (W_NOI || ' months')::INTERVAL)::DATE;
   ELSIF p_inst_freq = 'Q'
   THEN
      W_NOI :=
           FLOOR (
              DATE_PART ('month', AGE (p_ason_date, p_inst_from_date)) / 3)
         + 1;
      w_next_inst_date :=
         (p_inst_from_date + (3 * W_NOI || ' months')::INTERVAL)::DATE;
   ELSIF p_inst_freq = 'H'
   THEN
      W_NOI :=
           FLOOR (
              DATE_PART ('month', AGE (p_ason_date, p_inst_from_date)) / 6)
         + 1;
      w_next_inst_date :=
         (p_inst_from_date + (6 * W_NOI || ' months')::INTERVAL)::DATE;
   ELSIF p_inst_freq = 'Y'
   THEN
      W_NOI :=
           FLOOR (
              DATE_PART ('month', AGE (p_ason_date, p_inst_from_date)) / 12)
         + 1;
      w_next_inst_date :=
         (p_inst_from_date + (12 * W_NOI || ' months')::INTERVAL)::DATE;
   ELSIF p_inst_freq = 'D'
   THEN
      w_next_inst_date := p_ason_date + 1;
      W_NOI := p_inst_from_date - p_ason_date;
   END IF;

   RETURN w_next_inst_date;
EXCEPTION
   WHEN OTHERS
   THEN
      NULL;
END;
$$;


ALTER FUNCTION public.fn_get_next_installment_date(p_inst_freq character, p_inst_from_date date, p_ason_date date) OWNER TO postgres;

--
-- Name: fn_get_noof_installment_due(character, date, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_get_noof_installment_due(p_inst_freq character, p_inst_from_date date, p_ason_date date) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
   W_MESSAGE          CHARACTER (20);
   w_next_inst_date   DATE;
   O_ERRM             CHARACTER (100);
   W_STATUS           CHARACTER (20);
   W_NOI              INTEGER;
   W_NOD              INTEGER;
BEGIN
   IF p_inst_freq = 'W'
   THEN
      W_NOD := FLOOR ((p_ason_date - p_inst_from_date) / 7) * 7;
      w_next_inst_date := p_inst_from_date + W_NOD;
      W_NOI := FLOOR (W_NOD / 7) + 1;
   ELSIF p_inst_freq = 'M'
   THEN
      W_NOI := DATE_PART ('month', AGE (p_ason_date, p_inst_from_date));
      w_next_inst_date :=
         (p_inst_from_date + (W_NOI || ' months')::INTERVAL)::DATE;
   ELSIF p_inst_freq = 'Q'
   THEN
      W_NOI :=
         FLOOR (DATE_PART ('month', AGE (p_ason_date, p_inst_from_date)) / 3);
      w_next_inst_date :=
         (p_inst_from_date + (3 * W_NOI || ' months')::INTERVAL)::DATE;
   ELSIF p_inst_freq = 'H'
   THEN
      W_NOI :=
         FLOOR (DATE_PART ('month', AGE (p_ason_date, p_inst_from_date)) / 6);
      w_next_inst_date :=
         (p_inst_from_date + (6 * W_NOI || ' months')::INTERVAL)::DATE;
   ELSIF p_inst_freq = 'Y'
   THEN
      W_NOI :=
         FLOOR (
            DATE_PART ('month', AGE (p_ason_date, p_inst_from_date)) / 12);
      w_next_inst_date :=
         (p_inst_from_date + (12 * W_NOI || ' months')::INTERVAL)::DATE;
   ELSIF p_inst_freq = 'D'
   THEN
      w_next_inst_date := p_ason_date;
      W_NOI := (p_inst_from_date - p_ason_date) + 1;
   END IF;

   IF W_NOI < 0
   THEN
      W_NOI := 0;
   END IF;

   RETURN W_NOI;
EXCEPTION
   WHEN OTHERS
   THEN
      RETURN 0;
END;
$$;


ALTER FUNCTION public.fn_get_noof_installment_due(p_inst_freq character, p_inst_from_date date, p_ason_date date) OWNER TO postgres;

--
-- Name: fn_get_todays_due(character, date, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_get_todays_due(p_inst_freq character, p_inst_from_date date, p_ason_date date) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
   W_MESSAGE          CHARACTER (20);
   w_next_inst_date   DATE;
   O_ERRM             CHARACTER (100);
   W_STATUS           CHARACTER (20);
   W_NOI              INTEGER;
   W_NOD              INTEGER;
BEGIN
   IF p_inst_freq = 'W'
   THEN
      W_NOD := FLOOR ((p_ason_date - p_inst_from_date) / 7) * 7;
      w_next_inst_date := p_inst_from_date + W_NOD;
      W_NOI := W_NOI / 7;
   ELSIF p_inst_freq = 'M'
   THEN
      W_NOI := DATE_PART ('month', AGE (p_ason_date, p_inst_from_date));
      w_next_inst_date :=
         (p_inst_from_date + (W_NOI || ' months')::INTERVAL)::DATE;
   ELSIF p_inst_freq = 'Q'
   THEN
      W_NOI :=
         FLOOR (DATE_PART ('month', AGE (p_ason_date, p_inst_from_date)) / 3);
      w_next_inst_date :=
         (p_inst_from_date + (3 * W_NOI || ' months')::INTERVAL)::DATE;
   ELSIF p_inst_freq = 'H'
   THEN
      W_NOI :=
         FLOOR (DATE_PART ('month', AGE (p_ason_date, p_inst_from_date)) / 6);
      w_next_inst_date :=
         (p_inst_from_date + (6 * W_NOI || ' months')::INTERVAL)::DATE;
   ELSIF p_inst_freq = 'Y'
   THEN
      W_NOI :=
         FLOOR (
            DATE_PART ('month', AGE (p_ason_date, p_inst_from_date)) / 12);
      w_next_inst_date :=
         (p_inst_from_date + (12 * W_NOI || ' months')::INTERVAL)::DATE;
   ELSIF p_inst_freq = 'D'
   THEN
      W_NOD := p_ason_date - p_inst_from_date;
      w_next_inst_date := p_ason_date;
   END IF;

   IF w_next_inst_date = p_ason_date AND W_NOD >= 0
   THEN
      RETURN 1;
   ELSE
      RETURN 0;
   END IF;
EXCEPTION
   WHEN OTHERS
   THEN
      RETURN 0;
END;
$$;


ALTER FUNCTION public.fn_get_todays_due(p_inst_freq character, p_inst_from_date date, p_ason_date date) OWNER TO postgres;

--
-- Name: fn_get_todays_due_date(character, date, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_get_todays_due_date(p_inst_freq character, p_inst_from_date date, p_ason_date date) RETURNS date
    LANGUAGE plpgsql
    AS $$
DECLARE
   W_MESSAGE          CHARACTER (20);
   w_next_inst_date   DATE;
   O_ERRM             CHARACTER (100);
   W_STATUS           CHARACTER (20);
   W_NOI              INTEGER;
   W_NOD              INTEGER;
BEGIN
   IF p_inst_freq = 'W'
   THEN
      W_NOD := FLOOR ((p_ason_date - p_inst_from_date) / 7) * 7;
      w_next_inst_date := p_inst_from_date + W_NOD;
      W_NOI := W_NOI / 7;
   ELSIF p_inst_freq = 'M'
   THEN
      W_NOI := DATE_PART ('month', AGE (p_ason_date, p_inst_from_date));
      w_next_inst_date :=
         (p_inst_from_date + (W_NOI || ' months')::INTERVAL)::DATE;
   --w_return := W_NOI;
   ELSIF p_inst_freq = 'Q'
   THEN
      W_NOI :=
         FLOOR (DATE_PART ('month', AGE (p_ason_date, p_inst_from_date)) / 3);
      w_next_inst_date :=
         (p_inst_from_date + (3 * W_NOI || ' months')::INTERVAL)::DATE;
   ELSIF p_inst_freq = 'H'
   THEN
      W_NOI :=
         FLOOR (DATE_PART ('month', AGE (p_ason_date, p_inst_from_date)) / 6);
      w_next_inst_date :=
         (p_inst_from_date + (6 * W_NOI || ' months')::INTERVAL)::DATE;
   ELSIF p_inst_freq = 'Y'
   THEN
      W_NOI :=
         FLOOR (
            DATE_PART ('month', AGE (p_ason_date, p_inst_from_date)) / 12);
      w_next_inst_date :=
         (p_inst_from_date + (12 * W_NOI || ' months')::INTERVAL)::DATE;
   ELSIF p_inst_freq = 'D'
   THEN
      w_next_inst_date := p_ason_date;
   END IF;

   RETURN w_next_inst_date;
EXCEPTION
   WHEN OTHERS
   THEN
      RETURN 0;
END;
$$;


ALTER FUNCTION public.fn_get_todays_due_date(p_inst_freq character, p_inst_from_date date, p_ason_date date) OWNER TO postgres;

--
-- Name: fn_micfin_get_center_days(character, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_micfin_get_center_days(p_center_code character, p_ason_date date) RETURNS SETOF public.center_days_of_month
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_status             VARCHAR;
   w_errm               VARCHAR;
   w_month_start_date   DATE;
   w_first_week_day     DATE;
   w_next_week_day      DATE;
   result_record        center_days_of_month;
   w_center_day         INTEGER;
   w_current_month      INTEGER;
   w_next_month         INTEGER;
BEGIN
   SELECT cast (center_day AS INTEGER)
     INTO w_center_day
     FROM delar_center
    WHERE center_code = p_center_code;

   SELECT CAST (date_trunc ('month', p_ason_date) AS DATE)
     INTO w_month_start_date;

   SELECT date_part ('month', p_ason_date)
     INTO w_current_month;

   SELECT   w_month_start_date::DATE
          + (w_center_day + 7 - extract (DOW FROM w_month_start_date::DATE))::INT %
            7
   INTO w_next_week_day;

   result_record.center_week := '1st Week';
   result_record.center_date := w_next_week_day;
   result_record.center_begin_date = w_next_week_day - 7;
   RETURN NEXT
      result_record;

   FOR ind IN 2 .. 7
   LOOP
      SELECT date_part ('month', w_next_week_day)
        INTO w_next_month;

      IF w_current_month = w_next_month
      THEN
         result_record.center_begin_date = w_next_week_day;
         w_next_week_day := w_next_week_day + 7;

         SELECT date_part ('month', w_next_week_day)
           INTO w_next_month;

         IF w_current_month <> w_next_month
         THEN
            SELECT CAST (
                        date_trunc ('month', w_next_week_day)
                      + INTERVAL '1 months'
                      - INTERVAL '1 day' AS DATE) month_end
              INTO w_next_week_day;
         END IF;

         IF date_part ('month', w_next_week_day) <> w_current_month
         THEN
            EXIT;
         END IF;

         IF ind = 2
         THEN
            result_record.center_week := '2nd Week';
         END IF;

         IF ind = 3
         THEN
            result_record.center_week := '3rd Week';
         END IF;

         IF ind = 4
         THEN
            result_record.center_week := '4th Week';
         END IF;

         IF ind = 5
         THEN
            result_record.center_week := '5th Week';
         END IF;

         IF ind = 6
         THEN
            result_record.center_week := '6th Week';
         END IF;

         result_record.center_date := w_next_week_day;
         RETURN NEXT
            result_record;
      END IF;
   END LOOP;

   RETURN;
EXCEPTION
   WHEN OTHERS
   THEN
      w_errm := SQLERRM;

      INSERT INTO error_details
           VALUES (w_errm);
END;
$$;


ALTER FUNCTION public.fn_micfin_get_center_days(p_center_code character, p_ason_date date) OWNER TO postgres;

--
-- Name: fn_micfin_get_emi_detail_amount(character, date, character); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_micfin_get_emi_detail_amount(p_center_code character, p_ason_date date, p_client_id character, OUT o_total_emi_amount numeric, OUT o_total_emi_due numeric, OUT o_total_emi_recover numeric, OUT o_total_installment_amount numeric, OUT o_asonday_total_recover numeric, OUT o_asonday_due_recover numeric, OUT o_asonday_recover numeric, OUT o_asonday_advance_recover numeric, OUT o_asonday_profit_recover numeric) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   W_MESSAGE                    CHARACTER (20);
   W_RETURN                     NUMERIC (22, 2) := 0;
   w_emi_inst_amount            NUMERIC (22, 2) := 0;
   w_installment_due_amount     NUMERIC (22, 2) := 0;
   w_total_emi_due              NUMERIC (22, 2) := 0;
   w_total_emi_amount           NUMERIC (22, 2) := 0;
   w_total_emi_recover          NUMERIC (22, 2) := 0;
   w_total_emi_profit_payment   NUMERIC (22, 2) := 0;

   w_asonday_total_recover      NUMERIC (22, 2) := 0;
   w_asonday_due_recover        NUMERIC (22, 2) := 0;
   w_asonday_recover            NUMERIC (22, 2) := 0;
   w_asonday_advance_recover    NUMERIC (22, 2) := 0;
   O_STATUS                     CHARACTER (20);
   O_ERRM                       CHARACTER (100);
   W_STATUS                     CHARACTER (20);
BEGIN
   BEGIN
      SELECT sum (emi_inst_amount) emi_inst_amount,
             sum (
                (  (total_installment_due - total_installment_paid)
                 * emi_inst_amount)) installment_due_amount,
             sum (total_emi_due) total_emi_due,
             sum (total_emi_amount) total_emi_amount,
             sum (installment_tot_repay_amt) total_emi_recover
        INTO w_emi_inst_amount,
             w_installment_due_amount,
             w_total_emi_due,
             w_total_emi_amount,
             w_total_emi_recover
        FROM (SELECT emi_inst_amount,
                     total_emi_due,
                     total_emi_amount,
                     installment_tot_repay_amt,
                     total_installment_due,
                     total_installment_paid
                FROM (SELECT   fn_get_todays_due (emi_inst_frequency,
                                                  emi_inst_repay_from_date,
                                                  p_ason_date)
                             * emi_inst_amount emi_inst_amount,
                             total_emi_due,
                             total_emi_amount,
                             installment_tot_repay_amt,
                             fn_get_noof_installment_due (
                                emi_inst_frequency,
                                emi_inst_repay_from_date,
                                p_ason_date) total_installment_due,
                             CAST (
                                FLOOR (
                                     installment_tot_repay_amt
                                   / emi_inst_amount) AS INTEGER) total_installment_paid
                        FROM sales_emi_setup e
                       WHERE     e.center_code = p_center_code
                             AND e.total_emi_due > 0
                             AND e.emi_reference_date <= p_ason_date
                             AND (   e.emi_closer_date IS NULL
                                  OR emi_closer_date >= p_ason_date)) e) t;

      W_RETURN := COALESCE (w_installment_due_amount, 0.00);
   END;

   WITH
      emi_receive_amount
      AS
         (SELECT emi_inst_amount,
                 emi_rate,
                 inst_receive_amount,
                 total_due_recover,
                 principal_due_recover,
                 profit_due_recover,
                 emi_total_payment,
                 emi_principal_payment,
                 emi_profit_payment,
                 total_emi_outstanding,
                 emi_principal_outstanding,
                 emi_profit_outstanding,
                 emi_total_overdue,
                 emi_principal_overdue,
                 emi_profit_overdue,
                 total_advance_recover,
                 principal_advance_recover,
                 profit_advance_recover,
                 (CASE
                     WHEN (  inst_receive_amount
                           - total_advance_recover
                           - total_due_recover) >
                          0
                     THEN
                        (  inst_receive_amount
                         - total_advance_recover
                         - total_due_recover)
                     ELSE
                        0
                  END) ason_day_recover
            FROM sales_emi_history
           WHERE     center_code = p_center_code
                 AND inst_receive_date = p_ason_date),
      emi_recovery_summary
      AS
         (SELECT emi_inst_amount,
                 emi_rate,
                 inst_receive_amount,
                 total_due_recover,
                 total_advance_recover,
                 ason_day_recover,
                 emi_total_payment,
                 emi_principal_payment,
                 emi_profit_payment,
                 total_emi_outstanding,
                 emi_principal_outstanding,
                 emi_profit_outstanding,
                 emi_total_overdue,
                 emi_principal_overdue,
                 emi_profit_overdue,
                 principal_advance_recover,
                 profit_advance_recover
            FROM emi_receive_amount)
   SELECT sum (inst_receive_amount) total_recover_amount,
          sum (total_due_recover) total_due_recover,
          sum (ason_day_recover) total_ason_day_recover,
          sum (total_advance_recover) total_advance_recover,
          sum (emi_profit_payment) total_emi_profit_payment
     INTO w_asonday_total_recover,
          w_asonday_due_recover,
          w_asonday_recover,
          w_asonday_advance_recover,
          w_total_emi_profit_payment
     FROM emi_recovery_summary;

   o_total_emi_amount := COALESCE (w_total_emi_amount, 0.00);
   o_total_emi_due := COALESCE (w_total_emi_due, 0.00);
   o_total_installment_amount := COALESCE (w_emi_inst_amount, 0.00);
   o_total_emi_recover := COALESCE (w_total_emi_recover, 0.00);
   o_asonday_total_recover := COALESCE (w_asonday_total_recover, 0.00);
   o_asonday_due_recover := COALESCE (w_asonday_due_recover, 0.00);
   o_asonday_recover := COALESCE (w_asonday_recover, 0.00);
   o_asonday_advance_recover := COALESCE (w_asonday_advance_recover, 0.00);
   o_asonday_profit_recover := COALESCE (w_total_emi_profit_payment, 0.00);
END;
$$;


ALTER FUNCTION public.fn_micfin_get_emi_detail_amount(p_center_code character, p_ason_date date, p_client_id character, OUT o_total_emi_amount numeric, OUT o_total_emi_due numeric, OUT o_total_emi_recover numeric, OUT o_total_installment_amount numeric, OUT o_asonday_total_recover numeric, OUT o_asonday_due_recover numeric, OUT o_asonday_recover numeric, OUT o_asonday_advance_recover numeric, OUT o_asonday_profit_recover numeric) OWNER TO postgres;

--
-- Name: fn_run_micfin_collection_sheet(integer, character, date, character, character); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_run_micfin_collection_sheet(p_branch_code integer, p_center_code character, p_ason_date date, p_is_empty character, p_app_user_id character, OUT o_status character, OUT o_errm character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_errm                          VARCHAR;
   w_status                        VARCHAR;
   w_branch_name                   VARCHAR;
   w_center_name                   VARCHAR;
   w_center_day                    VARCHAR;
   w_center_region_id              VARCHAR;
   w_center_admin_code             VARCHAR;
   w_center_admin_name             VARCHAR;
   w_center_admin_phone            VARCHAR;
   w_center_employee_id            VARCHAR;
   w_center_start_time             VARCHAR;
   w_center_opening_date           DATE;
   w_report_month                  VARCHAR;
   w_field_officer_name            VARCHAR;
   rec_client_info                 RECORD;
   rec_center_date                 RECORD;
   w_month_start_date              DATE;
   w_month_end_date                DATE;
   w_monthly_sb_withdraw_date      VARCHAR;
   w_center_day_serial             INTEGER := 0;
   w_monthly_sb_opening_balance    NUMERIC (22, 2);
   w_sb_installment_amount         NUMERIC (22, 2);
   w_monthly_sb_withdraw           NUMERIC (22, 2);
   w_monthly_sb_closing_balance    NUMERIC (22, 2);
   w_monthly_emi_opening_balance   NUMERIC (22, 2);
   w_emi_installment_amount        NUMERIC (22, 2);
   w_monthly_emi_withdraw_date     DATE;
   w_monthly_emi_withdraw          NUMERIC (22, 2);
   w_monthly_emi_closing_balance   NUMERIC (22, 2);
   w_monthly_emi_payment           NUMERIC (22, 2);
   w_account_number                VARCHAR;
   w_sb_first_week_collect         NUMERIC (22, 2);
   w_sb_second_week_collect        NUMERIC (22, 2);
   w_sb_third_week_collect         NUMERIC (22, 2);
   w_sb_forth_week_collect         NUMERIC (22, 2);
   w_sb_fifth_week_collect         NUMERIC (22, 2);
   w_emi_first_week_collect        NUMERIC (22, 2);
   w_emi_second_week_collect       NUMERIC (22, 2);
   w_emi_third_week_collect        NUMERIC (22, 2);
   w_emi_forth_week_collect        NUMERIC (22, 2);
   w_emi_fifth_week_collect        NUMERIC (22, 2);
   w_emi_total_week_collect        NUMERIC (22, 2);
   w_monthly_emi_disburse          NUMERIC (22, 2);
   w_sb_total_week_collect         NUMERIC (22, 2);
   w_total_emi_disburse_amount     NUMERIC (22, 2);

   w_emi_sales_date                VARCHAR;
   w_emi_sales_amount              VARCHAR;
   w_emi_no_installment            VARCHAR;
   w_emi_inst_freq                 VARCHAR;
   w_emi_inst_amount               VARCHAR;
   w_emi_adv_receive               VARCHAR;
   w_total_emi_amount              VARCHAR;


   w_this_emi_sales_date           VARCHAR;
   w_this_emi_sales_amount         VARCHAR;
   w_this_emi_no_installment       VARCHAR;
   w_this_emi_inst_freq            VARCHAR;
   w_this_emi_inst_amount          VARCHAR;
   w_this_emi_adv_receive          VARCHAR;
   w_this_total_emi_amount         VARCHAR;
   w_sb_account_type               VARCHAR;
   w_emi_account_type              VARCHAR;
BEGIN
   SELECT CAST (date_trunc ('month', p_ason_date) AS DATE)
     INTO w_month_start_date;

   SELECT (  date_trunc ('month', p_ason_date::DATE)
           + INTERVAL '1 month'
           - INTERVAL '1 day')::DATE AS end_of_month
     INTO w_month_end_date;

   DELETE FROM micfin_inst_month_coll_sheet
         WHERE app_user_id = p_app_user_id;

   DELETE FROM micfin_sheet_user_param
         WHERE app_user_id = p_app_user_id;

   ---RAISE EXCEPTION USING MESSAGE = p_is_empty;

   SELECT tran_account_type
     INTO w_sb_account_type
     FROM finance_transaction_type
    WHERE transaction_screen = 'DEP_RECEIVE';

   SELECT tran_account_type
     INTO w_emi_account_type
     FROM finance_transaction_type
    WHERE transaction_screen = 'EMI_RECEIVE';

   FOR rec_client_info
      IN (  SELECT (ROW_NUMBER () OVER (ORDER BY cast (client_id AS INTEGER)))
                      serial_no,
                   client_id,
                   client_name,
                   client_father_name,
                   client_phone,
                   client_joining_date,
                   NULL
                      monthly_sb_opening_balance,
                   NULL
                      sb_first_week_collect,
                   NULL
                      sb_second_week_collect,
                   NULL
                      sb_third_week_collect,
                   NULL
                      sb_forth_week_collect,
                   NULL
                      sb_fifth_week_collect,
                   NULL
                      monthly_sb_withdraw_date,
                   NULL
                      monthly_sb_withdraw,
                   NULL
                      monthly_sb_closing_balance,
                   NULL
                      monthly_emi_opening_balance,
                   NULL
                      emi_first_week_collect,
                   NULL
                      emi_second_week_collect,
                   NULL
                      emi_third_week_collect,
                   NULL
                      emi_forth_week_collect,
                   NULL
                      emi_fifth_week_collect,
                   NULL
                      monthly_emi_withdraw_date,
                   NULL
                      monthly_emi_withdraw,
                   NULL
                      monthly_emi_closing_balance,
                   p_app_user_id
                      app_user_id,
                   current_timestamp
              FROM sales_clients
             WHERE     branch_code = p_branch_code
                   AND center_code = p_center_code
                   AND client_joining_date <= w_month_end_date
                   AND (   closing_date IS NULL
                        OR closing_date > w_month_start_date)
          ORDER BY cast (client_id AS INTEGER))
   LOOP
      IF p_is_empty = 'Y'
      THEN
         SELECT account_number, 0.00
           INTO w_account_number, w_sb_installment_amount
           FROM finance_accounts_balance
          WHERE     client_id = rec_client_info.client_id
                AND account_type = w_sb_account_type;

         IF w_sb_installment_amount <> 0
         THEN
            w_sb_first_week_collect := w_sb_installment_amount;
            w_sb_second_week_collect := w_sb_installment_amount;
            w_sb_third_week_collect := w_sb_installment_amount;
            w_sb_forth_week_collect := w_sb_installment_amount;
            w_sb_fifth_week_collect := w_sb_installment_amount;
         END IF;

         SELECT *
           INTO w_status, w_errm
           FROM fn_finance_acbal_hist (w_account_number, w_month_end_date);

         SELECT o_account_balance
         INTO w_monthly_sb_opening_balance
         FROM fn_finance_get_ason_acbal (w_account_number,
                                         w_month_start_date - 1);

         SELECT account_number
          INTO w_account_number
          FROM finance_accounts_balance
         WHERE     client_id = rec_client_info.client_id
               AND account_type = w_emi_account_type;

         SELECT sum (emi_inst_amount)
          INTO w_emi_installment_amount
          FROM sales_emi_setup
         WHERE     client_id = rec_client_info.client_id
               AND (   emi_closer_date IS NULL
                    OR emi_closer_date > w_month_start_date)
               AND emi_cancel_on IS NULL;

         IF w_emi_installment_amount <> 0
         THEN
            w_emi_first_week_collect := w_emi_installment_amount;
            w_emi_second_week_collect := w_emi_installment_amount;
            w_emi_third_week_collect := w_emi_installment_amount;
            w_emi_forth_week_collect := w_emi_installment_amount;
            w_emi_fifth_week_collect := w_emi_installment_amount;
         END IF;

         SELECT *
           INTO w_status, w_errm
           FROM fn_finance_acbal_hist (w_account_number, w_month_end_date);

         SELECT abs (o_account_balance)
         INTO w_monthly_emi_opening_balance
         FROM fn_finance_get_ason_acbal (w_account_number,
                                         w_month_start_date - 1);
      END IF;


      IF p_is_empty = 'N'
      THEN
         SELECT account_number, 0.00
           INTO w_account_number, w_sb_installment_amount
           FROM finance_accounts_balance
          WHERE     client_id = rec_client_info.client_id
                AND account_type = w_sb_account_type;

         SELECT *
           INTO w_status, w_errm
           FROM fn_finance_acbal_hist (w_account_number, w_month_end_date);

         SELECT o_account_balance
         INTO w_monthly_sb_opening_balance
         FROM fn_finance_get_ason_acbal (w_account_number,
                                         w_month_start_date - 1);

         --RAISE EXCEPTION USING MESSAGE = w_account_number;

         SELECT sum (payment_amount),
                STRING_AGG (TRIM (TO_CHAR (payment_date, 'DD')), ' , ') monthly_sb_withdraw_date
           INTO w_monthly_sb_withdraw, w_monthly_sb_withdraw_date
           FROM finance_deposit_payment
          WHERE     branch_code = p_branch_code
                AND center_code = p_center_code
                AND client_id = rec_client_info.client_id
                AND payment_date BETWEEN w_month_start_date
                                     AND w_month_end_date
                AND cancel_by IS NULL;


         FOR rec_center_date
            IN (SELECT center_week, center_begin_date, center_date
                  FROM fn_micfin_get_center_days (p_center_code, p_ason_date))
         LOOP
            w_center_day_serial := w_center_day_serial + 1;

            IF w_center_day_serial = 1
            THEN
               SELECT sum (total_credit_sum)
                INTO w_sb_first_week_collect
                FROM finance_accounts_balance_hist
               WHERE     account_number = w_account_number
                     AND branch_code = p_branch_code
                     AND transaction_date BETWEEN   rec_center_date.center_begin_date
                                                  + 1
                                              AND rec_center_date.center_date;
            ELSIF w_center_day_serial = 2
            THEN
               SELECT sum (total_credit_sum)
                INTO w_sb_second_week_collect
                FROM finance_accounts_balance_hist
               WHERE     account_number = w_account_number
                     AND branch_code = p_branch_code
                     AND transaction_date BETWEEN   rec_center_date.center_begin_date
                                                  + 1
                                              AND rec_center_date.center_date;
            ELSIF w_center_day_serial = 3
            THEN
               SELECT sum (total_credit_sum)
                INTO w_sb_third_week_collect
                FROM finance_accounts_balance_hist
               WHERE     account_number = w_account_number
                     AND branch_code = p_branch_code
                     AND transaction_date BETWEEN   rec_center_date.center_begin_date
                                                  + 1
                                              AND rec_center_date.center_date;
            ELSIF w_center_day_serial = 4
            THEN
               SELECT sum (total_credit_sum)
                INTO w_sb_forth_week_collect
                FROM finance_accounts_balance_hist
               WHERE     account_number = w_account_number
                     AND branch_code = p_branch_code
                     AND transaction_date BETWEEN   rec_center_date.center_begin_date
                                                  + 1
                                              AND rec_center_date.center_date;
            ELSIF w_center_day_serial = 5
            THEN
               SELECT sum (total_credit_sum)
                INTO w_sb_fifth_week_collect
                FROM finance_accounts_balance_hist
               WHERE     account_number = w_account_number
                     AND branch_code = p_branch_code
                     AND transaction_date BETWEEN   rec_center_date.center_begin_date
                                                  + 1
                                              AND rec_center_date.center_date;
            END IF;
         END LOOP;

         w_center_day_serial := 0;
         w_monthly_sb_closing_balance :=
              (  w_monthly_sb_opening_balance
               + COALESCE (w_sb_first_week_collect, 0.00)
               + COALESCE (w_sb_second_week_collect, 0.00)
               + COALESCE (w_sb_third_week_collect, 0.00)
               + COALESCE (w_sb_forth_week_collect, 0.00)
               + COALESCE (w_sb_fifth_week_collect, 0.00))
            - COALESCE (w_monthly_sb_withdraw, 0.00);
         w_sb_total_week_collect :=
            (  COALESCE (w_sb_first_week_collect, 0.00)
             + COALESCE (w_sb_second_week_collect, 0.00)
             + COALESCE (w_sb_third_week_collect, 0.00)
             + COALESCE (w_sb_forth_week_collect, 0.00)
             + COALESCE (w_sb_fifth_week_collect, 0.00));

         SELECT account_number
          INTO w_account_number
          FROM finance_accounts_balance
         WHERE     client_id = rec_client_info.client_id
               AND account_type = w_emi_account_type;

         SELECT *
           INTO w_status, w_errm
           FROM fn_finance_acbal_hist (w_account_number, w_month_end_date);

         SELECT abs (o_account_balance)
         INTO w_monthly_emi_opening_balance
         FROM fn_finance_get_ason_acbal (w_account_number,
                                         w_month_start_date - 1);

         SELECT sum (total_debit_sum), sum (total_credit_sum)
           INTO w_monthly_emi_disburse, w_monthly_emi_payment
           FROM finance_accounts_balance_hist
          WHERE     account_number = w_account_number
                AND branch_code = p_branch_code
                AND transaction_date BETWEEN w_month_start_date
                                         AND w_month_end_date;

         w_monthly_emi_withdraw := COALESCE (w_monthly_emi_withdraw, 0.00);
         w_monthly_emi_payment := COALESCE (w_monthly_emi_payment, 0.00);
         w_monthly_emi_disburse := COALESCE (w_monthly_emi_disburse, 0.00);

         w_monthly_emi_closing_balance :=
              (w_monthly_emi_opening_balance + w_monthly_emi_disburse)
            - w_monthly_emi_payment;

         FOR rec_center_date
            IN (SELECT center_week, center_begin_date, center_date
                  FROM fn_micfin_get_center_days (p_center_code, p_ason_date))
         LOOP
            w_center_day_serial := w_center_day_serial + 1;

            IF w_center_day_serial = 1
            THEN
               SELECT sum (total_credit_sum)
                INTO w_emi_first_week_collect
                FROM finance_accounts_balance_hist
               WHERE     account_number = w_account_number
                     AND branch_code = p_branch_code
                     AND transaction_date BETWEEN   rec_center_date.center_begin_date
                                                  + 1
                                              AND rec_center_date.center_date;
            ELSIF w_center_day_serial = 2
            THEN
               SELECT sum (total_credit_sum)
                INTO w_emi_second_week_collect
                FROM finance_accounts_balance_hist
               WHERE     account_number = w_account_number
                     AND branch_code = p_branch_code
                     AND transaction_date BETWEEN   rec_center_date.center_begin_date
                                                  + 1
                                              AND rec_center_date.center_date;
            ELSIF w_center_day_serial = 3
            THEN
               SELECT sum (total_credit_sum)
                INTO w_emi_third_week_collect
                FROM finance_accounts_balance_hist
               WHERE     account_number = w_account_number
                     AND branch_code = p_branch_code
                     AND transaction_date BETWEEN   rec_center_date.center_begin_date
                                                  + 1
                                              AND rec_center_date.center_date;
            ELSIF w_center_day_serial = 4
            THEN
               SELECT sum (total_credit_sum)
                INTO w_emi_forth_week_collect
                FROM finance_accounts_balance_hist
               WHERE     account_number = w_account_number
                     AND branch_code = p_branch_code
                     AND transaction_date BETWEEN   rec_center_date.center_begin_date
                                                  + 1
                                              AND rec_center_date.center_date;
            ELSIF w_center_day_serial = 5
            THEN
               SELECT sum (total_credit_sum)
                INTO w_emi_fifth_week_collect
                FROM finance_accounts_balance_hist
               WHERE     account_number = w_account_number
                     AND branch_code = p_branch_code
                     AND transaction_date BETWEEN   rec_center_date.center_begin_date
                                                  + 1
                                              AND rec_center_date.center_date;
            END IF;
         END LOOP;

         w_center_day_serial := 0;
      END IF;

      w_emi_total_week_collect :=
         (  COALESCE (w_emi_first_week_collect, 0.00)
          + COALESCE (w_emi_second_week_collect, 0.00)
          + COALESCE (w_emi_third_week_collect, 0.00)
          + COALESCE (w_emi_forth_week_collect, 0.00)
          + COALESCE (w_emi_fifth_week_collect, 0.00));


      BEGIN
         SELECT STRING_AGG (
                   TRIM (TO_CHAR (emi_reference_date, 'DD/MM/YYYY')),
                   ' + ')
                   emi_sales_date,
                STRING_AGG (
                   TRIM (
                      TO_CHAR (
                           COALESCE (emi_reference_amount, 0)
                         + COALESCE (emi_profit_amount, 0),
                         '999,999,999.99')),
                   ' + ')
                   emi_sales_amount,
                STRING_AGG (
                   TRIM (
                      TO_CHAR (COALESCE (number_of_installment, 0), '9999')),
                   ' + ')
                   emi_no_installment,
                STRING_AGG (TRIM (emi_inst_frequency), ' + ')
                   emi_inst_freq,
                STRING_AGG (
                   TRIM (TO_CHAR (COALESCE (emi_inst_amount, 0), '9999')),
                   ' + ')
                   emi_inst_amount,
                STRING_AGG (
                   TRIM (
                      TO_CHAR (COALESCE (emi_down_amount, 0),
                               '999,999,999.99')),
                   ' + ')
                   emi_adv_receive,
                STRING_AGG (
                   TRIM (
                      TO_CHAR (COALESCE (total_emi_amount, 0),
                               '999,999,999.99')),
                   ' + ')
                   total_emi_amount,
                sum (
                     COALESCE (emi_reference_amount, 0)
                   + COALESCE (emi_profit_amount, 0))
           INTO w_emi_sales_date,
                w_emi_sales_amount,
                w_emi_no_installment,
                w_emi_inst_freq,
                w_emi_inst_amount,
                w_emi_adv_receive,
                w_total_emi_amount,
                w_total_emi_disburse_amount
           FROM sales_emi_setup
          WHERE     client_id = rec_client_info.client_id
                AND emi_cancel_on IS NULL
                AND (   emi_closer_date > w_month_start_date
                     OR emi_closer_date IS NULL);
      END;

      BEGIN
         SELECT STRING_AGG (
                   TRIM (TO_CHAR (emi_reference_date, 'DD/MM/YYYY')),
                   ' + ') emi_sales_date,
                STRING_AGG (
                   TRIM (
                      TO_CHAR (
                           COALESCE (emi_reference_amount, 0)
                         + COALESCE (emi_profit_amount, 0),
                         '999,999,999.99')),
                   ' + ') emi_sales_amount,
                STRING_AGG (
                   TRIM (
                      TO_CHAR (COALESCE (number_of_installment, 0), '9999')),
                   ' + ') emi_no_installment,
                STRING_AGG (TRIM (emi_inst_frequency), ' + ') emi_inst_freq,
                STRING_AGG (
                   TRIM (TO_CHAR (COALESCE (emi_inst_amount, 0), '9999')),
                   ' + ') emi_inst_amount,
                STRING_AGG (
                   TRIM (
                      TO_CHAR (COALESCE (emi_down_amount, 0),
                               '999,999,999.99')),
                   ' + ') emi_adv_receive,
                STRING_AGG (
                   TRIM (
                      TO_CHAR (COALESCE (total_emi_amount, 0),
                               '999,999,999.99')),
                   ' + ') total_emi_amount
           INTO w_this_emi_sales_date,
                w_this_emi_sales_amount,
                w_this_emi_no_installment,
                w_this_emi_inst_freq,
                w_this_emi_inst_amount,
                w_this_emi_adv_receive,
                w_this_total_emi_amount
           FROM sales_emi_setup
          WHERE     client_id = rec_client_info.client_id
                AND emi_reference_date BETWEEN w_month_start_date
                                           AND w_month_end_date
                AND emi_cancel_on IS NULL;
      END;

      INSERT INTO micfin_inst_month_coll_sheet (serial_number,
                                                client_id,
                                                client_name,
                                                client_father_name,
                                                client_phone,
                                                client_joining_date,
                                                monthly_sb_opening_balance,
                                                sb_first_week_collect,
                                                sb_second_week_collect,
                                                sb_third_week_collect,
                                                sb_forth_week_collect,
                                                sb_fifth_week_collect,
                                                sb_total_week_collect,
                                                monthly_sb_withdraw_date,
                                                monthly_sb_withdraw,
                                                monthly_sb_closing_balance,
                                                monthly_emi_opening_balance,
                                                emi_sales_date,
                                                emi_sales_amount,
                                                total_emi_disburse_amount,
                                                emi_no_installment,
                                                emi_inst_freq,
                                                emi_inst_amount,
                                                this_month_sales_date,
                                                this_month_sales_amount,
                                                this_month_adv_amount,
                                                this_month_emi_due_after_adv,
                                                this_month_total_inst,
                                                this_month_inst_amount,
                                                this_month_inst_freq,
                                                emi_first_week_collect,
                                                emi_second_week_collect,
                                                emi_third_week_collect,
                                                emi_forth_week_collect,
                                                emi_fifth_week_collect,
                                                emi_total_week_collect,
                                                monthly_emi_disburse,
                                                monthly_emi_withdraw_date,
                                                monthly_emi_withdraw,
                                                monthly_emi_closing_balance,
                                                app_user_id,
                                                app_data_time)
           VALUES (rec_client_info.serial_no,
                   rec_client_info.client_id,
                   rec_client_info.client_name,
                   rec_client_info.client_father_name,
                   rec_client_info.client_phone,
                   rec_client_info.client_joining_date,
                   w_monthly_sb_opening_balance,
                   w_sb_first_week_collect,
                   w_sb_second_week_collect,
                   w_sb_third_week_collect,
                   w_sb_forth_week_collect,
                   w_sb_fifth_week_collect,
                   w_sb_total_week_collect,
                   w_monthly_sb_withdraw_date,
                   w_monthly_sb_withdraw,
                   w_monthly_sb_closing_balance,
                   w_monthly_emi_opening_balance,
                   w_emi_sales_date,
                   w_emi_sales_amount,
                   w_total_emi_disburse_amount,
                   w_emi_no_installment,
                   w_emi_inst_freq,
                   w_emi_inst_amount,
                   w_this_emi_sales_date,
                   w_this_emi_sales_amount,
                   w_this_emi_adv_receive,
                   w_this_total_emi_amount,
                   w_this_emi_no_installment,
                   w_this_emi_inst_amount,
                   w_this_emi_inst_freq,
                   w_emi_first_week_collect,
                   w_emi_second_week_collect,
                   w_emi_third_week_collect,
                   w_emi_forth_week_collect,
                   w_emi_fifth_week_collect,
                   w_emi_total_week_collect,
                   w_monthly_emi_disburse,
                   w_monthly_emi_withdraw_date,
                   w_monthly_emi_withdraw,
                   w_monthly_emi_closing_balance,
                   rec_client_info.app_user_id,
                   current_timestamp);
   END LOOP;

   SELECT branch_name
     INTO w_branch_name
     FROM appauth_branch
    WHERE branch_code = p_branch_code;

   SELECT branch_center_code || ' - ' || center_name,
          center_region_id,
          center_day,
          center_open_date,
          center_employee_id,
          center_admin_id,
          center_start_time
     INTO w_center_name,
          w_center_region_id,
          w_center_day,
          w_center_opening_date,
          w_center_employee_id,
          w_center_admin_code,
          w_center_start_time
     FROM delar_center
    WHERE center_code = p_center_code;

   SELECT admin_name, admin_mobile_num
     INTO w_center_admin_name, w_center_admin_phone
     FROM delar_center_admin
    WHERE admin_id = w_center_admin_code;

   IF w_center_day = '0'
   THEN
      w_center_day := 'Sunday';
   ELSIF w_center_day = '1'
   THEN
      w_center_day := 'Monday';
   ELSIF w_center_day = '2'
   THEN
      w_center_day := 'Tuesday';
   ELSIF w_center_day = '3'
   THEN
      w_center_day := 'Wednesday';
   ELSIF w_center_day = '4'
   THEN
      w_center_day := 'Thursday';
   ELSIF w_center_day = '5'
   THEN
      w_center_day := 'Friday';
   ELSIF w_center_day = '6'
   THEN
      w_center_day := 'Saturday';
   END IF;

   SELECT to_char (
             to_timestamp (date_part ('month', p_ason_date)::TEXT, 'MM'),
             'Month')
   INTO w_report_month;

   SELECT employee_name
     INTO w_field_officer_name
     FROM appauth_employees
    WHERE employee_id = w_center_employee_id;

   INSERT INTO micfin_sheet_user_param (branch_name,
                                        center_name,
                                        center_day,
                                        center_opening_date,
                                        report_month,
                                        field_officer_name,
                                        report_date,
                                        center_location,
                                        center_admin,
                                        center_admin_phone,
                                        center_start_time,
                                        app_user_id,
                                        app_data_time)
        VALUES (w_branch_name,
                w_center_name,
                w_center_day,
                w_center_opening_date,
                w_report_month,
                w_field_officer_name,
                p_ason_date,
                w_center_region_id,
                w_center_admin_name,
                w_center_admin_phone,
                w_center_start_time,
                p_app_user_id,
                current_timestamp);

   UPDATE micfin_sheet_user_param
      SET fifth_week_name = '', forth_week_name = '';

   FOR rec_center_date
      IN (SELECT center_week, center_begin_date, center_date
            FROM fn_micfin_get_center_days (p_center_code, p_ason_date))
   LOOP
      w_center_day_serial := w_center_day_serial + 1;

      IF w_center_day_serial = 1
      THEN
         UPDATE micfin_sheet_user_param
            SET first_week_name =
                      rec_center_date.center_week
                   || chr (10)
                   || rec_center_date.center_date,
                column_week5_value = ''
          WHERE app_user_id = p_app_user_id;
      ELSIF w_center_day_serial = 2
      THEN
         UPDATE micfin_sheet_user_param
            SET second_week_name =
                      rec_center_date.center_week
                   || chr (10)
                   || rec_center_date.center_date,
                column_week5_value = ''
          WHERE app_user_id = p_app_user_id;
      ELSIF w_center_day_serial = 3
      THEN
         UPDATE micfin_sheet_user_param
            SET third_week_name =
                      rec_center_date.center_week
                   || chr (10)
                   || rec_center_date.center_date,
                column_week5_value = ''
          WHERE app_user_id = p_app_user_id;
      ELSIF w_center_day_serial = 4
      THEN
         UPDATE micfin_sheet_user_param
            SET forth_week_name =
                      rec_center_date.center_week
                   || chr (10)
                   || rec_center_date.center_date,
                column_week5_value = ''
          WHERE app_user_id = p_app_user_id;
      ELSIF w_center_day_serial = 5
      THEN
         UPDATE micfin_sheet_user_param
            SET fifth_week_name =
                      rec_center_date.center_week
                   || chr (10)
                   || rec_center_date.center_date,
                column_week5_value = 'Y'
          WHERE app_user_id = p_app_user_id;
      END IF;
   END LOOP;

   o_status := 'S';
   o_errm := '';
EXCEPTION
   WHEN OTHERS
   THEN
      IF w_status = 'E'
      THEN
         o_status := w_status;
         o_errm := w_errm;
      ELSE
         o_errm := SQLERRM;
         o_status := 'E';
      END IF;
END;
$$;


ALTER FUNCTION public.fn_run_micfin_collection_sheet(p_branch_code integer, p_center_code character, p_ason_date date, p_is_empty character, p_app_user_id character, OUT o_status character, OUT o_errm character) OWNER TO postgres;

--
-- Name: fn_run_micfin_report(character, character); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_run_micfin_report(p_app_user_id character, p_report_name character, OUT o_status character, OUT o_errm character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_status                 VARCHAR;
   w_errm                   VARCHAR;
   w_sql_stat               TEXT := '';
   w_center_code            VARCHAR;
   w_from_date              DATE;
   w_upto_date              DATE;
   w_ason_date              DATE;
   w_current_business_day   DATE;
   w_ledger_code            VARCHAR;
   w_invoice_number         VARCHAR;
   w_user_id                VARCHAR;
   w_acc_type_code          VARCHAR;
   w_employee_id            VARCHAR;
   w_client_id              VARCHAR;
   w_supplier_id            VARCHAR;
   w_account_number         VARCHAR;
   w_account_title          VARCHAR;
   w_product_id             VARCHAR;
   w_branch_code            INTEGER;
   w_zero_balance           VARCHAR := 'N';
   w_transfer_tran          VARCHAR := 'N';
   w_closing_balance        NUMERIC (22, 2);
   w_opening_balance        NUMERIC (22, 2);
   w_cash_gl_code           VARCHAR;
   rec_delar_list           RECORD;
   rec_branch_list          RECORD;
   rec_product_list         RECORD;
   w_branch_name            VARCHAR;
   w_branch_address         VARCHAR;
   w_group_id               VARCHAR;
   w_app_user_id            VARCHAR;
BEGIN
   DELETE FROM appauth_report_table_tabular
         WHERE app_user_id = p_app_user_id;

   SELECT CASE WHEN parameter_values != '' THEN parameter_values END
    INTO w_center_code
    FROM appauth_report_parameter
   WHERE     parameter_name = 'p_center_code'
         AND report_name = p_report_name
         AND app_user_id = p_app_user_id;

   SELECT CASE
             WHEN parameter_values != ''
             THEN
                cast (parameter_values AS INTEGER)
          END w_branch_code
     INTO w_branch_code
     FROM appauth_report_parameter
    WHERE     parameter_name = 'p_branch_code'
          AND report_name = p_report_name
          AND app_user_id = p_app_user_id;

   SELECT CASE
             WHEN parameter_values != '' THEN cast (parameter_values AS DATE)
          END p_from_date
     INTO w_from_date
     FROM appauth_report_parameter
    WHERE     parameter_name = 'p_from_date'
          AND report_name = p_report_name
          AND app_user_id = p_app_user_id;

   SELECT CASE
             WHEN parameter_values != '' THEN cast (parameter_values AS DATE)
          END p_upto_date
     INTO w_upto_date
     FROM appauth_report_parameter
    WHERE     parameter_name = 'p_upto_date'
          AND report_name = p_report_name
          AND app_user_id = p_app_user_id;

   SELECT CASE
             WHEN parameter_values != '' THEN cast (parameter_values AS DATE)
          END p_ason_date
     INTO w_ason_date
     FROM appauth_report_parameter
    WHERE     parameter_name = 'p_ason_date'
          AND report_name = p_report_name
          AND app_user_id = p_app_user_id;

   IF w_from_date = w_upto_date AND w_ason_date IS NULL
   THEN
      w_ason_date := w_upto_date;
   END IF;

   IF p_report_name = 'micfin_emicollect_report'
   THEN
      SELECT CASE WHEN parameter_values != '' THEN parameter_values END
       INTO w_employee_id
       FROM appauth_report_parameter
      WHERE     parameter_name = 'p_employee_id'
            AND report_name = p_report_name
            AND app_user_id = p_app_user_id;

      w_sql_stat :=
            'INSERT INTO appauth_report_table_tabular (report_column1,
                                          report_column2,
                                          report_column3,
                                          report_column4,
                                          report_column5,
                                          report_column6,
                                          report_column7,
                                          report_column8,
                                          report_column9,
                                          report_column10,
                                          report_column11,
                                          report_column12,
                                          report_column13,
                                          report_column14,
                                          report_column15,
                                          report_column16,
                                          report_column17,
                                          report_column18,
                                          report_column19,
                                          report_column20,
                                          app_user_id)
   WITH
      emi_setup
      AS
         (SELECT c.branch_center_code || '' - '' || c.center_name center_name,
                 employee_name, a.account_number,
                 e.client_id,
                 a.account_title,
                 a.phone_number,
                 emi_reference_no,
                 total_emi_amount,
                 number_of_installment,
                 emi_rate,
                 emi_inst_amount inst_amount,
                 emi_inst_repay_from_date inst_from_date,
                 emi_inst_frequency inst_freq,
                 e.center_code,
                 installment_tot_repay_amt,
                 fn_get_noof_installment_due (e.emi_inst_frequency,
                                              e.emi_inst_repay_from_date,
                                              '''
         || w_ason_date
         || ''')
                    noof_installment_due,
                 fn_get_todays_due (e.emi_inst_frequency,
                                    e.emi_inst_repay_from_date,
                                    '''
         || w_ason_date
         || ''')
                    is_todays_due, 
                 fn_get_next_installment_date (emi_inst_frequency,
                                               emi_inst_repay_from_date,
                                               current_date) next_inst_date
            FROM sales_emi_setup e,
                 finance_accounts_balance a,
                 delar_center c,
                 appauth_employees em
           WHERE     e.account_number = a.account_number
                 AND c.center_code = e.center_code
                 AND c.center_employee_id = em.employee_id 
                 AND e.emi_reference_date <= '''
         || w_ason_date
         || '''
                 and ( e.emi_closer_date is null or emi_closer_date>='''
         || w_ason_date
         || ''')';

      IF w_branch_code IS NOT NULL
      THEN
         w_sql_stat := w_sql_stat || ' and e.branch_code = ' || w_branch_code;
      END IF;

      IF w_center_code IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and e.center_code = ''' || w_center_code || '''';
      END IF;

      IF w_employee_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and em.employee_id = ''' || w_employee_id || '''';
      END IF;

      w_sql_stat :=
            w_sql_stat
         || '),
      emi_details
      AS
         (SELECT s.center_name,
                 s.employee_name,
                 s.account_number,
                 s.center_code,
                 s.client_id,
                 s.installment_tot_repay_amt,
                 s.account_title,
                 s.phone_number,
                 s.emi_reference_no,
                 s.total_emi_amount,
                 s.number_of_installment,
                 s.emi_rate,
                 s.inst_amount,
                 s.inst_from_date,
                 s.next_inst_date,s.is_todays_due,
                 s.inst_freq, noof_installment_due total_due_inst, (noof_installment_due* s.inst_amount) inst_due_amount,
                 COALESCE (b.emi_total_payment, 0.00) emi_total_payment
            FROM emi_setup s
                 LEFT OUTER JOIN
                 (SELECT h.branch_code,
                         h.account_number,
                         h.emi_reference_no emi_reference_no,
                         h.emi_total_payment
                    FROM sales_emi_history h,
                         (  SELECT b.account_number,
                                   b.emi_reference_no,
                                   max (inst_receive_date) inst_receive_date
                              FROM sales_emi_history b, emi_setup e
                             WHERE     b.account_number = e.account_number
                                   AND b.emi_reference_no = e.emi_reference_no
                                   AND b.inst_receive_date <= '''
         || w_ason_date
         || '''
                          GROUP BY b.account_number, b.emi_reference_no) l
                   WHERE     h.account_number = l.account_number
                         AND h.emi_reference_no = l.emi_reference_no
                         AND h.inst_receive_date = l.inst_receive_date) b
                    ON     (s.account_number = b.account_number)
                       AND s.emi_reference_no = b.emi_reference_no),
      emi_receive_details
      AS
         (SELECT s.center_name,
                 s.employee_name,
                 s.account_number,
                 s.center_code,
                 s.client_id,
                 s.installment_tot_repay_amt,
                 s.account_title,
                 s.phone_number,
                 s.emi_reference_no,
                 s.total_emi_amount,
                 s.number_of_installment,
                 s.emi_rate,
                 s.inst_amount,
                 s.inst_from_date,
                 s.next_inst_date,
                 s.inst_freq,s.is_todays_due,
                 COALESCE (emi_total_payment, 0.00) emi_total_payment,
                 COALESCE (total_due_inst, 0) total_due_inst,
                 COALESCE (inst_due_amount, 0.00) inst_due_amount,
                 COALESCE (inst_receive_amount, 0.00) inst_receive_amount
            FROM emi_details s
                 LEFT OUTER JOIN
                 (SELECT h.branch_code,
                         h.account_number,
                         h.emi_reference_no emi_reference_no,
                         h.inst_receive_amount
                    FROM sales_emi_history h, emi_setup e
                   WHERE     h.account_number = e.account_number
                         AND h.emi_reference_no = e.emi_reference_no
                         AND h.inst_receive_date = '''
         || w_ason_date
         || ''') b
                    ON     (s.account_number = b.account_number)
                       AND s.emi_reference_no = b.emi_reference_no)
     SELECT client_id || '' - '' || account_title client_name,
            account_title,
		    center_name,
            employee_name,
            phone_number,
            emi_reference_no,
            total_emi_amount,
            number_of_installment,
            installment_tot_repay_amt,
            inst_amount,
            inst_from_date,
            next_inst_date,
            inst_freq,
            total_due_inst,
            (CASE
                WHEN (inst_due_amount - installment_tot_repay_amt) > 0
                THEN
                   (inst_due_amount - installment_tot_repay_amt)
                ELSE
                   0
             END) inst_due_amount,
            inst_receive_amount,
            (CASE
                WHEN (inst_amount*is_todays_due - inst_receive_amount) > 0
                THEN
                   (inst_amount*is_todays_due - inst_receive_amount)
                ELSE
                   0
             END) todays_due_amount,
            emi_total_payment,
            (CASE
                WHEN (inst_due_amount - emi_total_payment) > 0
                THEN
                   (inst_due_amount - emi_total_payment)
                ELSE
                   0
             END) inst_od_amount,
            (CASE
                WHEN (emi_total_payment - inst_due_amount) > 0
                THEN
                   (emi_total_payment - inst_due_amount)
                ELSE
                   0
             END) inst_adv_amount,
         '''
         || p_app_user_id
         || '''
       FROM emi_receive_details 
   ORDER BY employee_name, center_name, account_title';

      ---RAISE EXCEPTION USING MESSAGE = w_sql_stat;

      EXECUTE w_sql_stat;
   ELSIF p_report_name = 'micfin_collectiondetails_report'
   THEN
      SELECT CASE WHEN parameter_values != '' THEN parameter_values END
       INTO w_employee_id
       FROM appauth_report_parameter
      WHERE     parameter_name = 'p_employee_id'
            AND report_name = p_report_name
            AND app_user_id = p_app_user_id;

      SELECT CASE WHEN parameter_values != '' THEN parameter_values END
       INTO w_app_user_id
       FROM appauth_report_parameter
      WHERE     parameter_name = 'p_app_user_id'
            AND report_name = p_report_name
            AND app_user_id = p_app_user_id;

      SELECT CASE WHEN parameter_values != '' THEN parameter_values END
       INTO w_client_id
       FROM appauth_report_parameter
      WHERE     parameter_name = 'p_client_id'
            AND report_name = p_report_name
            AND app_user_id = p_app_user_id;

      w_sql_stat :=
         'INSERT INTO appauth_report_table_tabular (report_column1,
                                          report_column2,
                                          report_column3,
                                          report_column4,
                                          report_column5,
                                          report_column6,
                                          report_column7,
                                          report_column8,
                                          report_column9,
                                          report_column10,
                                          report_column11,
                                          report_column12,
                                          report_column13,
                                          report_column14,
                                          app_user_id)
   WITH
      receive_payment
      AS
         (SELECT branch_code,
                 center_code,
                 client_id,
                 ''Deposit Receive'' transaction_type,
                 deposit_date transaction_date,
                 (deposit_amount - cancel_amount) receive_amount,
                 0  payment_amount,
                 narration narration,
                 to_char (app_data_time, ''DD-MM-YYYY: HH12:MI:SS AM'') posting_time
            FROM finance_deposit_receive
           WHERE cancel_by IS NULL ';

      IF w_branch_code IS NOT NULL
      THEN
         w_sql_stat := w_sql_stat || ' and branch_code = ' || w_branch_code;
      END IF;

      IF w_center_code IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and center_code = ''' || w_center_code || '''';
      END IF;

      IF w_app_user_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and app_user_id = ''' || w_app_user_id || '''';
      END IF;

      IF w_client_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and client_id = ''' || w_client_id || '''';
      END IF;

      IF w_ason_date IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and deposit_date = ''' || w_ason_date || '''';
      END IF;

      IF w_from_date IS NOT NULL AND w_upto_date IS NOT NULL
      THEN
         w_sql_stat :=
               w_sql_stat
            || ' and deposit_date between '''
            || w_from_date
            || ''' and '''
            || w_upto_date
            || '''';
      END IF;

      w_sql_stat :=
            w_sql_stat
         || ' UNION ALL
          SELECT branch_code,
                 center_code,
                 client_id,
                 ''Deposit Payment'' transaction_type,
                 payment_date transaction_date,
                 0  receive_amount,
                 payment_amount - cancel_amount payment_amount,
                 narration narration,
                 to_char (app_data_time, ''DD-MM-YYYY: HH12:MI:SS AM'') posting_time
            FROM finance_deposit_payment
           WHERE cancel_by IS NULL ';

      IF w_branch_code IS NOT NULL
      THEN
         w_sql_stat := w_sql_stat || ' and branch_code = ' || w_branch_code;
      END IF;

      IF w_center_code IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and center_code = ''' || w_center_code || '''';
      END IF;

      IF w_app_user_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and app_user_id = ''' || w_app_user_id || '''';
      END IF;

      IF w_client_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and client_id = ''' || w_client_id || '''';
      END IF;

      IF w_ason_date IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and payment_date = ''' || w_ason_date || '''';
      END IF;

      IF w_from_date IS NOT NULL AND w_upto_date IS NOT NULL
      THEN
         w_sql_stat :=
               w_sql_stat
            || ' and payment_date between '''
            || w_from_date
            || ''' and '''
            || w_upto_date
            || '''';
      END IF;

      w_sql_stat :=
            w_sql_stat
         || ' UNION ALL
          SELECT branch_code,
                 center_code,
                 client_id,
                 ''Emi Receive'' transaction_type,
                 receive_date transaction_date,
                 receive_amount + penalty_charge receive_amount,
                 0  payment_amount,
                 transaction_narration narration,
                 to_char (app_data_time, ''DD-MM-YYYY: HH12:MI:SS AM'') posting_time
            FROM sales_emi_receive
           WHERE emi_cancel_by IS NULL ';

      IF w_branch_code IS NOT NULL
      THEN
         w_sql_stat := w_sql_stat || ' and branch_code = ' || w_branch_code;
      END IF;

      IF w_center_code IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and center_code = ''' || w_center_code || '''';
      END IF;

      IF w_app_user_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and app_user_id = ''' || w_app_user_id || '''';
      END IF;

      IF w_client_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and client_id = ''' || w_client_id || '''';
      END IF;

      IF w_ason_date IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and receive_date = ''' || w_ason_date || '''';
      END IF;

      IF w_from_date IS NOT NULL AND w_upto_date IS NOT NULL
      THEN
         w_sql_stat :=
               w_sql_stat
            || ' and receive_date between '''
            || w_from_date
            || ''' and '''
            || w_upto_date
            || '''';
      END IF;

      w_sql_stat :=
            w_sql_stat
         || '
          UNION ALL
          SELECT branch_code,
                 center_code,
                 client_id,
                 fee_type || '' Fees Receive'' transaction_type,
                 fee_collection_date transaction_date,
                 fee_amount - cancel_amount receive_amount,
                 0  payment_amount,
                 transaction_narration narration,
                 to_char (app_data_time, ''DD-MM-YYYY: HH12:MI:SS AM'') posting_time
            FROM sales_fees_history
           WHERE cancel_by IS NULL ';

      IF w_branch_code IS NOT NULL
      THEN
         w_sql_stat := w_sql_stat || ' and branch_code = ' || w_branch_code;
      END IF;

      IF w_center_code IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and center_code = ''' || w_center_code || '''';
      END IF;

      IF w_app_user_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and app_user_id = ''' || w_app_user_id || '''';
      END IF;

      IF w_client_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and client_id = ''' || w_client_id || '''';
      END IF;

      IF w_ason_date IS NOT NULL
      THEN
         w_sql_stat :=
               w_sql_stat
            || ' and fee_collection_date = '''
            || w_ason_date
            || '''';
      END IF;

      IF w_from_date IS NOT NULL AND w_upto_date IS NOT NULL
      THEN
         w_sql_stat :=
               w_sql_stat
            || ' and fee_collection_date between '''
            || w_from_date
            || ''' and '''
            || w_upto_date
            || '''';
      END IF;

      w_sql_stat := w_sql_stat || ' ),
      transaction_details
      AS
         (SELECT t.branch_code,
                 t.client_id,
                 c.client_name,
                 t.center_code,
                 e.employee_id,
                 e.employee_name,
                 r.branch_center_code,
                 r.branch_center_code || ''-'' || r.center_name center_name,
                 receive_amount,
                 payment_amount,
                 transaction_type,
                 to_char (transaction_date, ''DD-MM-YYYY'') transaction_date,
                 narration,
                 posting_time
            FROM receive_payment t,
                 sales_clients c,
                 delar_center r,
                 appauth_employees e
           WHERE     t.client_id = c.client_id
                 AND t.center_code = r.center_code
                 AND e.employee_id = r.center_employee_id)
   SELECT t.*, ''' || p_app_user_id || ''' app_user_id
     FROM transaction_details t';

      EXECUTE w_sql_stat;
   END IF;

   o_status := 'S';
   o_errm := '';
EXCEPTION
   WHEN OTHERS
   THEN
      o_errm := SQLERRM;
      o_status := 'E';
END;
$$;


ALTER FUNCTION public.fn_run_micfin_report(p_app_user_id character, p_report_name character, OUT o_status character, OUT o_errm character) OWNER TO postgres;

--
-- Name: fn_run_purchase_report(character, character); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_run_purchase_report(p_app_user_id character, p_report_name character, OUT o_status character, OUT o_errm character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_status                 VARCHAR;
   w_errm                   VARCHAR;
   w_sql_stat               TEXT := '';
   w_center_code            VARCHAR;
   w_from_date              DATE;
   w_upto_date              DATE;
   w_ason_date              DATE;
   w_current_business_day   DATE;
   w_ledger_code            VARCHAR;
   w_invoice_number         VARCHAR;
   w_user_id                VARCHAR;
   w_acc_type_code          VARCHAR;
   w_employee_id            VARCHAR;
   w_client_id              VARCHAR;
   w_supplier_id            VARCHAR;
   w_account_number         VARCHAR;
   w_account_title          VARCHAR;
   w_product_id             VARCHAR;
   w_branch_code            INTEGER;
   w_zero_balance           VARCHAR := 'N';
   w_transfer_tran          VARCHAR := 'N';
   w_closing_balance        NUMERIC (22, 2);
   w_opening_balance        NUMERIC (22, 2);
   w_cash_gl_code           VARCHAR;
   rec_delar_list           RECORD;
   rec_branch_list          RECORD;
   rec_product_list         RECORD;
   w_branch_name            VARCHAR;
   w_branch_address         VARCHAR;
   w_group_id               VARCHAR;
   w_brand_id               VARCHAR;
BEGIN
   DELETE FROM appauth_report_table_tabular
         WHERE app_user_id = p_app_user_id;

   SELECT CASE WHEN parameter_values != '' THEN parameter_values END
    INTO w_center_code
    FROM appauth_report_parameter
   WHERE     parameter_name = 'p_center_code'
         AND report_name = p_report_name
         AND app_user_id = p_app_user_id;

   SELECT CASE
             WHEN parameter_values != ''
             THEN
                cast (parameter_values AS INTEGER)
          END w_branch_code
     INTO w_branch_code
     FROM appauth_report_parameter
    WHERE     parameter_name = 'p_branch_code'
          AND report_name = p_report_name
          AND app_user_id = p_app_user_id;

   SELECT CASE WHEN parameter_values != '' THEN parameter_values END w_group_id
     INTO w_group_id
     FROM appauth_report_parameter
    WHERE     parameter_name = 'p_group_id'
          AND report_name = p_report_name
          AND app_user_id = p_app_user_id;

   SELECT CASE WHEN parameter_values != '' THEN parameter_values END w_group_id
     INTO w_brand_id
     FROM appauth_report_parameter
    WHERE     parameter_name = 'p_brand_id'
          AND report_name = p_report_name
          AND app_user_id = p_app_user_id;

   SELECT CASE
             WHEN parameter_values != '' THEN cast (parameter_values AS DATE)
          END p_from_date
     INTO w_from_date
     FROM appauth_report_parameter
    WHERE     parameter_name = 'p_from_date'
          AND report_name = p_report_name
          AND app_user_id = p_app_user_id;

   SELECT CASE
             WHEN parameter_values != '' THEN cast (parameter_values AS DATE)
          END p_upto_date
     INTO w_upto_date
     FROM appauth_report_parameter
    WHERE     parameter_name = 'p_upto_date'
          AND report_name = p_report_name
          AND app_user_id = p_app_user_id;

   SELECT CASE
             WHEN parameter_values != '' THEN cast (parameter_values AS DATE)
          END p_ason_date
     INTO w_ason_date
     FROM appauth_report_parameter
    WHERE     parameter_name = 'p_ason_date'
          AND report_name = p_report_name
          AND app_user_id = p_app_user_id;

   IF w_from_date = w_upto_date AND w_ason_date IS NULL
   THEN
      w_ason_date := w_upto_date;
   END IF;

   IF p_report_name = 'daywise_purchase_list'
   THEN
      SELECT CASE WHEN parameter_values != '' THEN parameter_values END
       INTO w_product_id
       FROM appauth_report_parameter
      WHERE     parameter_name = 'p_product_id'
            AND report_name = p_report_name
            AND app_user_id = p_app_user_id;


      w_sql_stat :=
            'INSERT INTO appauth_report_table_tabular (report_column1,
                                             report_column2,
                                             report_column3,
                                             report_column4,
                                             report_column5,
                                             report_column6,
                                             report_column7,
                                             report_column8,
                                             app_user_id )
select p.product_id, p.product_model, p.product_name, TO_CHAR(s.stock_date ,''DD-MM-YYYY''), s.purces_price, s.quantity, s.purces_price*s.quantity total_price,
ROW_NUMBER () OVER (ORDER BY s.stock_date,p.product_name) ROW_NUMBER,
'''
         || p_app_user_id
         || '''
 from sales_stockdetails s, sales_products p
  where s.product_id=p.product_id 
  and status=''S''';

      IF w_from_date IS NOT NULL AND w_upto_date IS NOT NULL
      THEN
         w_sql_stat :=
               w_sql_stat
            || ' and s.stock_date between '''
            || w_from_date
            || ''' and '''
            || w_upto_date
            || '''';
      END IF;

      IF w_ason_date IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and s.stock_date = ''' || w_ason_date || '''';
      END IF;

      IF w_product_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and p.product_id = ''' || w_product_id || '''';
      END IF;

      IF w_group_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and p.product_group = ''' || w_group_id || '''';
      END IF;

      IF w_brand_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and p.brand_id = ''' || w_brand_id || '''';
      END IF;

      IF w_branch_code IS NOT NULL
      THEN
         w_sql_stat := w_sql_stat || ' and s.branch_code = ' || w_branch_code;
      END IF;

      w_sql_stat := w_sql_stat || ' order by s.stock_date,p.product_name';

      -- RAISE EXCEPTION USING MESSAGE = w_sql_stat;

      EXECUTE w_sql_stat;
   ELSIF p_report_name = 'sales_purchasenreturn_details'
   THEN
      SELECT CASE WHEN parameter_values != '' THEN parameter_values END w_account_number
        INTO w_account_number
        FROM appauth_report_parameter
       WHERE     parameter_name = 'p_supplier_account'
             AND report_name = p_report_name
             AND app_user_id = p_app_user_id;

      SELECT CASE WHEN parameter_values != '' THEN parameter_values END w_account_number
        INTO w_product_id
        FROM appauth_report_parameter
       WHERE     parameter_name = 'p_product_id'
             AND report_name = p_report_name
             AND app_user_id = p_app_user_id;

      IF w_account_number IS NOT NULL
      THEN
         SELECT DISTINCT client_id
           INTO w_supplier_id
           FROM finance_accounts_balance
          WHERE account_number = w_account_number;
      END IF;

      w_sql_stat :=
         'INSERT INTO appauth_report_table_tabular (report_column1,
                                        report_column2,
                                        report_column3,
                                        report_column4,
                                        report_column5,
                                        report_column6,
                                        report_column7,
                                        report_column8,
                                        report_column9,
                                        report_column10,
                                        report_column11,
                                        app_user_id)
   SELECT COALESCE (p.supplier_id, r.supplier_id) supplier_id,
          '' '' supplier_name,
          COALESCE (p.product_id, r.product_id) product_id,
             COALESCE (p.product_name, r.product_name)
          || ''(''
          || COALESCE (p.product_model, r.product_model, '' '')
          || '')'' product_name,
          COALESCE (p.stock_date, r.return_date) transaction_date,
          COALESCE (p.quantity, 0) purces_quantity,
          COALESCE (p.purces_rate, 0) purces_rate,
          COALESCE (p.total_price, 0) purces_total_price,
          COALESCE (r.returned_quantity, 0) returned_quantity,
          COALESCE (r.return_rate, 0) return_rate,
          COALESCE (r.return_amount, 0) return_total_price,
          ''' || p_app_user_id || '''
     FROM (SELECT d.supplier_id,
                  p.product_id,
                  d.stock_date,
                  p.product_model,
                  p.product_name,
                  d.quantity,
                  d.purces_price purces_rate,
                  d.total_price
             FROM sales_stockdetails d, sales_products p
            WHERE d.product_id = p.product_id 
            and status =''S''';

      IF w_from_date IS NOT NULL AND w_upto_date IS NOT NULL
      THEN
         w_sql_stat :=
               w_sql_stat
            || ' and d.stock_date between '''
            || w_from_date
            || ''' and '''
            || w_upto_date
            || '''';
      END IF;

      IF w_branch_code IS NOT NULL
      THEN
         w_sql_stat := w_sql_stat || ' and d.branch_code = ' || w_branch_code;
      END IF;

      IF w_product_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and d.product_id = ''' || w_product_id || '''';
      END IF;

      IF w_group_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and p.product_group = ''' || w_group_id || '''';
      END IF;

      IF w_brand_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and p.brand_id = ''' || w_brand_id || '''';
      END IF;

      IF w_supplier_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and d.supplier_id = ''' || w_supplier_id || '''';
      END IF;

      IF w_ason_date IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and d.stock_date = ''' || w_ason_date || '''';
      END IF;

      w_sql_stat :=
            w_sql_stat
         || '  ) p
          FULL OUTER JOIN
          (SELECT r.supplier_id,
                  p.product_id,
                  r.return_date,
                  p.product_model,
                  p.product_name,
                  r.returned_quantity,
                  round((r.return_amount / r.returned_quantity),2) return_rate,
                  r.return_amount
             FROM sales_stock_return_details r, sales_products p
            WHERE r.product_id = p.product_id ';

      IF w_from_date IS NOT NULL AND w_upto_date IS NOT NULL
      THEN
         w_sql_stat :=
               w_sql_stat
            || ' and r.return_date between '''
            || w_from_date
            || ''' and '''
            || w_upto_date
            || '''';
      END IF;

      IF w_branch_code IS NOT NULL
      THEN
         w_sql_stat := w_sql_stat || ' and r.branch_code = ' || w_branch_code;
      END IF;

      IF w_supplier_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and r.supplier_id = ''' || w_supplier_id || '''';
      END IF;

      IF w_product_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and r.product_id = ''' || w_product_id || '''';
      END IF;

      IF w_group_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and p.product_group = ''' || w_group_id || '''';
      END IF;

      IF w_brand_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and p.brand_id = ''' || w_brand_id || '''';
      END IF;

      IF w_ason_date IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and r.return_date = ''' || w_ason_date || '''';
      END IF;

      w_sql_stat := w_sql_stat || '  ) r
             ON (    p.product_id = r.product_id
                 AND p.supplier_id = r.supplier_id
                 AND r.return_date = p.stock_date)';

      --RAISE EXCEPTION USING MESSAGE = w_sql_stat;
      EXECUTE w_sql_stat;

      BEGIN
         FOR rec_branch_list
            IN (SELECT DISTINCT client_id, account_title
                  FROM finance_accounts_balance,
                       (SELECT DISTINCT report_column1
                          FROM appauth_report_table_tabular) s
                 WHERE report_column1 = client_id)
         LOOP
            UPDATE appauth_report_table_tabular
               SET report_column2 =
                         rec_branch_list.client_id
                      || '-'
                      || rec_branch_list.account_title
             WHERE report_column1 = rec_branch_list.client_id;
         END LOOP;
      END;
   ELSIF p_report_name = 'sales_purchasenreturnstmt_details'
   THEN
      SELECT CASE WHEN parameter_values != '' THEN parameter_values END w_account_number
        INTO w_account_number
        FROM appauth_report_parameter
       WHERE     parameter_name = 'p_supplier_account'
             AND report_name = p_report_name
             AND app_user_id = p_app_user_id;

      SELECT CASE WHEN parameter_values != '' THEN parameter_values END w_account_number
        INTO w_product_id
        FROM appauth_report_parameter
       WHERE     parameter_name = 'p_product_id'
             AND report_name = p_report_name
             AND app_user_id = p_app_user_id;

      IF w_account_number IS NOT NULL
      THEN
         SELECT DISTINCT client_id, account_title
           INTO w_supplier_id, w_account_title
           FROM finance_accounts_balance
          WHERE account_number = w_account_number;
      END IF;

      SELECT w_status, w_errm
        INTO w_status, w_errm
        FROM fn_finance_acbal_hist (w_account_number, w_from_date);

      BEGIN
         INSERT INTO appauth_report_parameter (app_user_id,
                                               report_name,
                                               parameter_name,
                                               parameter_values)
              VALUES (p_app_user_id,
                      p_report_name,
                      'p_supplier_name',
                      w_account_title);
      END;

      w_sql_stat :=
                      'INSERT INTO appauth_report_table_tabular (report_column1,
                                        report_column2,
                                        report_column3,
                                        report_column4,
                                        report_column5,
                                        report_column6,
                                        report_column7,
                                        report_column8,
                                        report_column9,
                                        report_column10,
                                        report_column11,
                                        report_column12,
                                        report_column13,
                                        report_column14,
                                        report_column15,
                                        report_column16,
                                        report_column17,
                                        report_column18,
                                        app_user_id)
   SELECT '''
                   || w_supplier_id
                   || ''' supplier_id,
          '''
                   || w_account_title
                   || ''' supplier_name,
          product_id,
          product_name,
          transaction_date,
          COALESCE (purces_quantity,0) purces_quantity,
          COALESCE (purces_rate,0.00) purces_rate,
          COALESCE (purces_total_price,0.00) purces_total_price,
          0.00,
          COALESCE (purces_total_price,0.00) purces_total_price,
          COALESCE (returned_quantity,0) returned_quantity,
          COALESCE (return_rate,0.00) return_rate,
          COALESCE (return_total_price,0.00) return_total_price,
          row_serial,
          total_row,
          (CASE WHEN row_serial = ''1'' THEN credit_balance ELSE 0 END)
             credit_balance,
          (CASE WHEN row_serial = ''1'' THEN debit_balance ELSE 0 END)
             debit_balance,
          account_balance,
          '''
                   || p_app_user_id
                   || '''
     FROM (SELECT '' supplier_id,
                  '' supplier_name,
                  product_id,
                  COALESCE (product_name,transaction_narration) product_name,
                  transaction_date,
                  purces_quantity,
                  purces_rate,
                  purces_total_price,
                  returned_quantity,
                  return_rate,
                  return_total_price,
                  credit_balance,
                  debit_balance,
                  account_balance,
                  (CASE
                      WHEN (ROW_NUMBER ()
                            OVER (PARTITION BY transaction_date
                                  ORDER BY transaction_date, product_name)) =
                           1
                      THEN
                         ''1''
                      ELSE
                         ''''
                   END) row_serial,
                  count (transaction_date)
                     OVER (PARTITION BY transaction_date) total_row
             FROM (SELECT supplier_id,
                          supplier_name,
                          product_id,
                          product_name,
                          COALESCE (s.transaction_date, t.transaction_date)
                             transaction_date,transaction_narration,
                          purces_quantity,
                          purces_rate,
                          purces_total_price,
                          returned_quantity,
                          return_rate,
                          return_total_price,
                          credit_balance,
                          debit_balance,
                          account_balance
                     FROM (SELECT COALESCE (p.supplier_id, r.supplier_id)
                                     supplier_id,
                                  '' ''
                                     supplier_name,
                                  COALESCE (p.product_id, r.product_id)
                                     product_id,
                                     COALESCE (p.product_name,
                                               r.product_name)
                                  || ''(''
                                  || COALESCE (p.product_model,
                                               r.product_model,
                                               '' '')
                                  || '')''
                                     product_name,
                                  COALESCE (p.stock_date, r.return_date)
                                     transaction_date,
                                  COALESCE (p.quantity, 0)
                                     purces_quantity,
                                  COALESCE (p.purces_rate, 0)
                                     purces_rate,
                                  COALESCE (p.total_price, 0)
                                     purces_total_price,
                                  COALESCE (r.returned_quantity, 0)
                                     returned_quantity,
                                  COALESCE (r.return_rate, 0)
                                     return_rate,
                                  COALESCE (r.return_amount, 0)
                                     return_total_price
                             FROM (SELECT d.supplier_id,
                                          p.product_id,
                                          d.stock_date,
                                          p.product_model,
                                          p.product_name,
                                          d.quantity,
                                          d.purces_price purces_rate,
                                          d.total_price
                                     FROM sales_stockdetails d,
                                          sales_products p
                                    WHERE d.product_id = p.product_id and status =''S'' and d.supplier_id='''
                   || w_supplier_id
                   || ''' and d.stock_date between '''
                   || w_from_date
                   || ''' and '''
                   || w_upto_date
                   || ''') p
                                  FULL OUTER JOIN
                                  (SELECT r.supplier_id,
                                          p.product_id,
                                          r.return_date,
                                          p.product_model,
                                          p.product_name,
                                          r.returned_quantity,
                                          round (
                                             (  r.return_amount
                                              / r.returned_quantity),
                                             2) return_rate,
                                          r.return_amount
                                     FROM sales_stock_return_details r,
                                          sales_products p
                                    WHERE r.product_id = p.product_id and r.supplier_id='''
                   || w_supplier_id
                   || ''' and r.return_date between '''
                   || w_from_date
                   || ''' and '''
                   || w_upto_date
                   || ''' ) r
                                     ON (    p.product_id = r.product_id
                                         AND p.supplier_id = r.supplier_id
                                         AND r.return_date = p.stock_date)) S
                          FULL OUTER JOIN
                          (SELECT transaction_date,transaction_narration,
                                  credit_balance,
                                  debit_balance,
                                  SUM (credit_balance - debit_balance)
                                     OVER (ORDER BY serial_number) account_balance
                             FROM (SELECT 1  serial_number,
                                    '''
                   || w_from_date
                 - 1
              || '''  transaction_date,''Opening Balance'' transaction_narration,
                                          (CASE
                                              WHEN o_account_balance > 0
                                              THEN
                                                 o_account_balance
                                              ELSE
                                                 0
                                           END) credit_balance,
                                          (CASE
                                              WHEN o_account_balance < 0
                                              THEN
                                                 abs (o_account_balance)
                                              ELSE
                                                 0
                                           END) debit_balance
                                     FROM fn_finance_get_ason_acbal ('''
              || w_account_number
              || ''', '''
              || w_from_date
            - 1
         || ''')
                                   UNION ALL
                                     SELECT   (ROW_NUMBER ()
                                               OVER (ORDER BY transaction_date))
                                            + 1
                                               serial_number,
                                            transaction_date,STRING_AGG (transaction_narration, '','') transaction_narration,
                                            sum (credit_balance)
                                               credit_balance,
                                            sum (debit_balance)
                                               debit_balance
                                       FROM (SELECT transaction_date,
                                                    transaction_narration,
                                                    (CASE
                                                        WHEN tran_debit_credit =
                                                             ''C''
                                                        THEN
                                                           tran_amount
                                                        ELSE
                                                           0
                                                     END) credit_balance,
                                                    (CASE
                                                        WHEN tran_debit_credit =
                                                             ''D''
                                                        THEN
                                                           tran_amount
                                                        ELSE
                                                           0
                                                     END) debit_balance
                                               FROM finance_transaction_details
                                              WHERE     account_number ='''
         || w_account_number
         || '''
                                                    AND cancel_by IS NULL
                                                    AND transaction_date BETWEEN '''
         || w_from_date
         || '''
                                                                       AND   '''
         || w_upto_date
         || ''' )
                                            t
                                   GROUP BY transaction_date) a
                            WHERE serial_number >= 1) T
                             ON (T.transaction_date = S.transaction_date)) t)
          t';

      --RAISE EXCEPTION USING MESSAGE = w_sql_stat;

      EXECUTE w_sql_stat;
   ELSIF p_report_name = 'sales_inventory_balance'
   THEN
      SELECT CASE WHEN parameter_values != '' THEN parameter_values END w_product_id
        INTO w_product_id
        FROM appauth_report_parameter
       WHERE     parameter_name = 'p_product_id'
             AND report_name = p_report_name
             AND app_user_id = p_app_user_id;

      IF COALESCE (w_branch_code, 0) = 0
      THEN
         BEGIN
            FOR rec_branch_list IN (  SELECT branch_code
                                        FROM appauth_branch
                                    ORDER BY branch_code)
            LOOP
               FOR rec_product_list
                  IN (SELECT product_id FROM sales_products)
               LOOP
                  SELECT *
                  INTO w_status, w_status
                  FROM fn_sales_product_inventory_hist (
                          rec_branch_list.branch_code,
                          rec_product_list.product_id);
               END LOOP;
            END LOOP;
         END;
      ELSE
         FOR rec_product_list IN (SELECT product_id FROM sales_products)
         LOOP
            SELECT *
            INTO w_status, w_status
            FROM fn_sales_product_inventory_hist (
                    w_branch_code,
                    rec_product_list.product_id);
         END LOOP;
      END IF;

      w_sql_stat :=
            'INSERT INTO appauth_report_table_tabular (report_column1,
                                        report_column2,
                                        report_column3,
                                        report_column4,
                                        report_column5,
                                        report_column6,
                                        report_column7,
                                        report_column8,
                                        report_column9,
                                        report_column10,
                                        report_column11,
                                        report_column12,
                                        report_column13,
                                        report_column14,
                                        report_column15,
                                        report_column16,
                                        report_column17,
                                        report_column18,
                                        report_column19, 
                                        report_column20,
                                        app_user_id)
  SELECT t.product_id,
         p.product_name || '' ('' || p.product_model || '')'' product_name,
         COALESCE (t.opening_purchase_rate, 0) opening_purchase_rate,
         COALESCE (t.opening_available_stock, 0) opening_available_stock,
           COALESCE (t.opening_available_stock, 0)
         * COALESCE (t.opening_purchase_rate, 0) product_opening_value,
         COALESCE (t.product_total_stock, 0) product_total_stock,
         COALESCE (t.total_order_quantity, 0) total_order_quantity,
         COALESCE (t.product_total_sales, 0) product_total_sales,
         COALESCE (t.total_stock_return, 0) total_stock_return,
         COALESCE (t.total_sales_return, 0) total_sales_return,
         COALESCE (t.product_total_damage, 0) product_total_damage,
         COALESCE (t.product_end_balance, 0) product_end_balance,
         COALESCE (t.total_purchase_amount, 0) total_purchase_amount,
         COALESCE (t.total_sales_amount, 0) total_sales_amount,
         COALESCE (t.stock_return_amount, 0) stock_return_amount,
         COALESCE (t.sales_return_amount, 0) sales_return_amount,
         COALESCE (t.total_damage_amount, 0) total_damage_amount,
         COALESCE (t.closing_purchase_rate, 0) closing_purchase_rate,
         COALESCE (t.closing_available_stock, 0) closing_available_stock,
           COALESCE (t.closing_available_stock, 0)
         * COALESCE (t.closing_purchase_rate, 0) product_closing_value,'''
         || p_app_user_id
         || '''
       FROM ( SELECT product_id,
                   sum (product_available_stock) product_available_stock,
                   sum (product_total_stock) product_total_stock,
                   sum (total_order_quantity) total_order_quantity,
                   sum (product_total_sales) product_total_sales,
                   sum (total_stock_return) total_stock_return,
                   sum (total_sales_return) total_sales_return,
                   sum (product_total_damage) product_total_damage,
                   sum (total_purchase_amount) total_purchase_amount,
                   sum (total_sales_amount) total_sales_amount,
                   sum (stock_return_amount) stock_return_amount,
                   sum (sales_return_amount) sales_return_amount,
                   sum (total_damage_amount) total_damage_amount,
                   sum (opening_purchase_rate) opening_purchase_rate,
                   sum (opening_available_stock) opening_available_stock,
                   sum (closing_available_stock) closing_available_stock,
                   sum (closing_purchase_rate) closing_purchase_rate,
                   sum (product_end_balance) product_end_balance
              FROM (SELECT COALESCE (b.product_id, t.product_id, e.product_id)
                    product_id,
                 COALESCE (b.opening_available_stock, 0)
                    product_available_stock,
                 t.product_total_stock,
                 t.total_order_quantity,
                 t.product_total_sales,
                 t.total_stock_return,
                 t.total_sales_return,
                 t.product_total_damage,
                 t.total_purchase_amount,
                 t.total_sales_amount,
                 t.stock_return_amount,
                 t.sales_return_amount,
                 t.total_damage_amount,
                 b.opening_purchase_rate,
                 b.opening_available_stock,
                 e.closing_available_stock,
                 e.closing_purchase_rate,
                 (  COALESCE (b.opening_available_stock, 0)
                  + COALESCE (t.product_total_stock, 0)
                  + COALESCE (t.total_sales_return, 0)
                  - COALESCE (t.product_total_sales, 0)
                  - COALESCE (t.total_stock_return, 0)
                  - COALESCE (t.product_total_damage, 0))
                    product_end_balance
            FROM (SELECT h.product_id,
                         h.product_available_stock opening_available_stock,
                         h.product_purchase_rate opening_purchase_rate
                    FROM sales_products_inventory_hist h,
                         (  SELECT product_id,
                                   max (inv_balance_date) inv_balance_date
                              FROM sales_products_inventory_hist
                                WHERE inv_balance_date < '''
         || w_from_date
         || '''';

      IF w_branch_code IS NOT NULL
      THEN
         w_sql_stat := w_sql_stat || ' and branch_code = ' || w_branch_code;
      END IF;

      IF w_product_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and product_id = ''' || w_product_id || '''';
      END IF;

      w_sql_stat :=
            w_sql_stat
         || ' GROUP BY product_id) b
                      WHERE     h.product_id = b.product_id
                            AND h.inv_balance_date = b.inv_balance_date) b
                    FULL OUTER JOIN
                    (  SELECT h.product_id,
                           sum (h.product_total_stock)
                              product_total_stock,
                           sum (h.total_order_quantity)
                              total_order_quantity,
                           sum (h.product_total_sales)
                              product_total_sales,
                           sum (h.total_stock_return)
                              total_stock_return,
                           sum (h.total_sales_return)
                              total_sales_return,
                           sum (h.product_total_damage)
                              product_total_damage,
                           sum (h.total_purchase_amount)
                              total_purchase_amount,
                           sum (h.total_purchase_balance)
                              total_purchase_balance,
                           sum (h.total_sales_amount)
                              total_sales_amount,
                           sum (h.total_sales_balance)
                              total_sales_balance,
                           sum (h.stock_return_amount)
                              stock_return_amount,
                           sum (h.sales_return_amount)
                              sales_return_amount,
                           sum (h.total_damage_amount)
                              total_damage_amount,
                           sum (h.cost_of_good_sold_balance)
                              cost_of_good_sold_balance,
                           sum (h.total_discount_receive)
                              total_discount_receive,
                           sum (h.total_discount_pay)
                              total_discount_pay
                         FROM sales_products_inventory_hist h
                        WHERE inv_balance_date between '''
         || w_from_date
         || ''' and '''
         || w_upto_date
         || '''';

      IF w_branch_code IS NOT NULL
      THEN
         w_sql_stat := w_sql_stat || ' and h.branch_code = ' || w_branch_code;
      END IF;

      IF w_product_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and h.product_id = ''' || w_product_id || '''';
      END IF;

      w_sql_stat :=
            w_sql_stat
         || ' GROUP BY h.product_id) t
                       ON (b.product_id = t.product_id)
                       FULL OUTER JOIN
                 (SELECT h.product_id,
                         h.product_available_stock closing_available_stock,
                         h.product_purchase_rate closing_purchase_rate
                    FROM sales_products_inventory_hist h,
                         (  SELECT product_id,
                                   max (inv_balance_date) inv_balance_date
                              FROM sales_products_inventory_hist
                             WHERE     inv_balance_date <= '''
         || w_upto_date
         || '''';

      IF w_branch_code IS NOT NULL
      THEN
         w_sql_stat := w_sql_stat || ' and branch_code = ' || w_branch_code;
      END IF;

      IF w_product_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and product_id = ''' || w_product_id || '''';
      END IF;

      w_sql_stat :=
            w_sql_stat
         || '     GROUP BY product_id) b
                   WHERE     h.product_id = b.product_id
                         AND h.inv_balance_date = b.inv_balance_date) e
                    ON (t.product_id = e.product_id)) d group by product_id) t,
            sales_products p
      WHERE p.product_id = t.product_id ';

      IF w_group_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and p.product_group = ''' || w_group_id || '''';
      END IF;

      IF w_brand_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and p.brand_id = ''' || w_brand_id || '''';
      END IF;

      w_sql_stat := w_sql_stat || ' ORDER BY p.product_name ';

      --RAISE EXCEPTION USING MESSAGE = w_sql_stat;

      EXECUTE w_sql_stat;
   END IF;

   o_status := 'S';
   o_errm := '';
EXCEPTION
   WHEN OTHERS
   THEN
      o_errm := SQLERRM;
      o_status := 'E';
END;
$$;


ALTER FUNCTION public.fn_run_purchase_report(p_app_user_id character, p_report_name character, OUT o_status character, OUT o_errm character) OWNER TO postgres;

--
-- Name: fn_run_report(character, character); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_run_report(p_app_user_id character, p_report_name character, OUT o_status character, OUT o_errm character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_status                 VARCHAR;
   w_errm                   VARCHAR;
   w_sql_stat               TEXT := '';
   w_center_code            VARCHAR;
   w_from_date              DATE;
   w_upto_date              DATE;
   w_ason_date              DATE;
   w_current_business_day   DATE;
   w_ledger_code            VARCHAR;
   w_invoice_number         VARCHAR;
   w_user_id                VARCHAR;
   w_acc_type_code          VARCHAR;
   w_employee_id            VARCHAR;
   w_client_id              VARCHAR;
   w_supplier_id            VARCHAR;
   w_account_number         VARCHAR;
   w_account_title          VARCHAR;
   w_product_id             VARCHAR;
   w_branch_code            INTEGER;
   w_zero_balance           VARCHAR := 'N';
   w_transfer_tran          VARCHAR := 'N';
   w_delar_id               INTEGER;
   w_closing_balance        NUMERIC (22, 2);
   w_opening_balance        NUMERIC (22, 2);
   w_cash_gl_code           VARCHAR;
   rec_delar_list           RECORD;
   rec_branch_list          RECORD;
   rec_product_list         RECORD;
   w_branch_name            VARCHAR;
   w_branch_address         VARCHAR;
   w_empty_sheet            VARCHAR;
   w_center_name            VARCHAR;
   w_center_address         VARCHAR;
BEGIN
   DELETE FROM appauth_report_table_tabular
         WHERE app_user_id = p_app_user_id;

   SELECT CASE WHEN parameter_values != '' THEN parameter_values END
    INTO w_center_code
    FROM appauth_report_parameter
   WHERE     parameter_name = 'p_center_code'
         AND report_name = p_report_name
         AND app_user_id = p_app_user_id;

   SELECT CASE WHEN parameter_values != '' THEN parameter_values END w_user_id
     INTO w_user_id
     FROM appauth_report_parameter
    WHERE     parameter_name = 'p_user_id'
          AND report_name = p_report_name
          AND app_user_id = p_app_user_id;

   SELECT CASE
             WHEN parameter_values != ''
             THEN
                cast (parameter_values AS INTEGER)
          END w_branch_code
     INTO w_branch_code
     FROM appauth_report_parameter
    WHERE     parameter_name = 'p_branch_code'
          AND report_name = p_report_name
          AND app_user_id = p_app_user_id;

   IF w_branch_code IS NOT NULL
   THEN
      SELECT branch_name, branch_address
        INTO w_branch_name, w_branch_address
        FROM appauth_branch
       WHERE branch_code = w_branch_code;

      BEGIN
         INSERT INTO appauth_report_parameter (app_user_id,
                                               report_name,
                                               parameter_name,
                                               parameter_values)
              VALUES (p_app_user_id,
                      p_report_name,
                      'p_branch_name',
                      w_branch_name);

         INSERT INTO appauth_report_parameter (app_user_id,
                                               report_name,
                                               parameter_name,
                                               parameter_values)
              VALUES (p_app_user_id,
                      p_report_name,
                      'p_branch_address',
                      w_branch_address);
      END;
   END IF;

   IF w_center_code IS NOT NULL
   THEN
      SELECT center_name, center_address
        INTO w_center_name, w_center_address
        FROM delar_center
       WHERE center_code = w_center_code;

      BEGIN
         INSERT INTO appauth_report_parameter (app_user_id,
                                               report_name,
                                               parameter_name,
                                               parameter_values)
              VALUES (p_app_user_id,
                      p_report_name,
                      'p_center_name',
                      w_center_name);

         INSERT INTO appauth_report_parameter (app_user_id,
                                               report_name,
                                               parameter_name,
                                               parameter_values)
              VALUES (p_app_user_id,
                      p_report_name,
                      'p_center_address',
                      w_center_address);
      END;
   END IF;


   SELECT CASE
             WHEN parameter_values != '' THEN cast (parameter_values AS DATE)
          END p_from_date
     INTO w_from_date
     FROM appauth_report_parameter
    WHERE     parameter_name = 'p_from_date'
          AND report_name = p_report_name
          AND app_user_id = p_app_user_id;

   SELECT CASE
             WHEN parameter_values != '' THEN cast (parameter_values AS DATE)
          END p_upto_date
     INTO w_upto_date
     FROM appauth_report_parameter
    WHERE     parameter_name = 'p_upto_date'
          AND report_name = p_report_name
          AND app_user_id = p_app_user_id;

   SELECT CASE
             WHEN parameter_values != '' THEN cast (parameter_values AS DATE)
          END p_ason_date
     INTO w_ason_date
     FROM appauth_report_parameter
    WHERE     parameter_name = 'p_ason_date'
          AND report_name = p_report_name
          AND app_user_id = p_app_user_id;

   IF w_from_date = w_upto_date AND w_ason_date IS NULL
   THEN
      w_ason_date := w_upto_date;
   END IF;
IF p_report_name IN ('sales_inventory_balance',
                           'sales_purchasenreturnstmt_details',
                           'sales_purchasenreturn_details',
                           'daywise_purchase_list')
   THEN
      SELECT *
        INTO w_status, w_errm
        FROM fn_run_purchase_report (p_app_user_id, p_report_name);

      IF w_status = 'E'
      THEN
         RAISE EXCEPTION USING MESSAGE = w_errm;
      END IF;
   ELSIF p_report_name IN ('sales_invoice',
                           'sales_daywisesales',
                           'sales_and_return_details',
                           'sales_and_return_statement',
                           'sales_profit_and_loss',
                           'sales_details_report')
   THEN
      SELECT *
        INTO w_status, w_errm
        FROM fn_run_sales_report (p_app_user_id, p_report_name);

      IF w_status = 'E'
      THEN
         RAISE EXCEPTION USING MESSAGE = w_errm;
      END IF;
   ELSIF p_report_name = 'micfin_monthly_collection_sheet'
   THEN
      SELECT parameter_values
       INTO w_empty_sheet
       FROM appauth_report_parameter
      WHERE     parameter_name = 'p_empty_sheet'
            AND report_name = p_report_name
            AND app_user_id = p_app_user_id;

      SELECT *
        INTO w_status, w_errm
        FROM fn_run_micfin_collection_sheet (w_branch_code,
                                             w_center_code,
                                             w_ason_date,
                                             w_empty_sheet,
                                             p_app_user_id);

      IF w_status = 'E'
      THEN
         RAISE EXCEPTION USING MESSAGE = w_errm;
      END IF;
   ELSIF p_report_name IN
            ('micfin_emicollect_report', 'micfin_collectiondetails_report')
   THEN
      SELECT *
        INTO w_status, w_errm
        FROM fn_run_micfin_report (p_app_user_id, p_report_name);

      IF w_status = 'E'
      THEN
         RAISE EXCEPTION USING MESSAGE = w_errm;
      END IF;
   ELSIF p_report_name IN ('center_sales_details')
   THEN
      SELECT *
        INTO w_status, w_errm
        FROM fn_run_sales_center_report (p_app_user_id, p_report_name);

      IF w_status = 'E'
      THEN
         RAISE EXCEPTION USING MESSAGE = w_errm;
      END IF;
   END IF;

   o_status := 'S';
   o_errm := '';
EXCEPTION
   WHEN OTHERS
   THEN
      o_errm := SQLERRM;
      o_status := 'E';
END;
$$;


ALTER FUNCTION public.fn_run_report(p_app_user_id character, p_report_name character, OUT o_status character, OUT o_errm character) OWNER TO postgres;

--
-- Name: fn_run_sales_center_report(character, character); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_run_sales_center_report(p_app_user_id character, p_report_name character, OUT o_status character, OUT o_errm character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_status                 VARCHAR;
   w_errm                   VARCHAR;
   w_sql_stat               TEXT := '';
   w_center_code            VARCHAR;
   w_from_date              DATE;
   w_upto_date              DATE;
   w_ason_date              DATE;
   w_current_business_day   DATE;
   w_ledger_code            VARCHAR;
   w_invoice_number         VARCHAR;
   w_user_id                VARCHAR;
   w_acc_type_code          VARCHAR;
   w_employee_id            VARCHAR;
   w_client_id              VARCHAR;
   w_supplier_id            VARCHAR;
   w_account_number         VARCHAR;
   w_account_title          VARCHAR;
   w_product_id             VARCHAR;
   w_branch_code            INTEGER;
   w_zero_balance           VARCHAR := 'N';
   w_transfer_tran          VARCHAR := 'N';
   w_closing_balance        NUMERIC (22, 2);
   w_opening_balance        NUMERIC (22, 2);
   w_cash_gl_code           VARCHAR;
   rec_delar_list           RECORD;
   rec_branch_list          RECORD;
   rec_product_list         RECORD;
   w_branch_name            VARCHAR;
   w_branch_address         VARCHAR;
   w_group_id               VARCHAR;
   w_brand_id               VARCHAR;
   w_sales_report_type      VARCHAR;
BEGIN
   DELETE FROM appauth_report_table_tabular
         WHERE app_user_id = p_app_user_id;

   SELECT CASE WHEN parameter_values != '' THEN parameter_values END
    INTO w_center_code
    FROM appauth_report_parameter
   WHERE     parameter_name = 'p_center_code'
         AND report_name = p_report_name
         AND app_user_id = p_app_user_id;

   SELECT CASE
             WHEN parameter_values != ''
             THEN
                cast (parameter_values AS INTEGER)
          END w_branch_code
     INTO w_branch_code
     FROM appauth_report_parameter
    WHERE     parameter_name = 'p_branch_code'
          AND report_name = p_report_name
          AND app_user_id = p_app_user_id;

   SELECT CASE WHEN parameter_values != '' THEN parameter_values END w_group_id
     INTO w_group_id
     FROM appauth_report_parameter
    WHERE     parameter_name = 'p_group_id'
          AND report_name = p_report_name
          AND app_user_id = p_app_user_id;

   SELECT CASE WHEN parameter_values != '' THEN parameter_values END w_group_id
     INTO w_brand_id
     FROM appauth_report_parameter
    WHERE     parameter_name = 'p_brand_id'
          AND report_name = p_report_name
          AND app_user_id = p_app_user_id;

   SELECT CASE
             WHEN parameter_values != '' THEN cast (parameter_values AS DATE)
          END p_from_date
     INTO w_from_date
     FROM appauth_report_parameter
    WHERE     parameter_name = 'p_from_date'
          AND report_name = p_report_name
          AND app_user_id = p_app_user_id;

   SELECT CASE
             WHEN parameter_values != '' THEN cast (parameter_values AS DATE)
          END p_upto_date
     INTO w_upto_date
     FROM appauth_report_parameter
    WHERE     parameter_name = 'p_upto_date'
          AND report_name = p_report_name
          AND app_user_id = p_app_user_id;

   SELECT CASE
             WHEN parameter_values != '' THEN cast (parameter_values AS DATE)
          END p_ason_date
     INTO w_ason_date
     FROM appauth_report_parameter
    WHERE     parameter_name = 'p_ason_date'
          AND report_name = p_report_name
          AND app_user_id = p_app_user_id;

   IF w_from_date = w_upto_date AND w_ason_date IS NULL
   THEN
      w_ason_date := w_upto_date;
   END IF;

   IF p_report_name = 'center_sales_details'
   THEN
      SELECT CASE WHEN parameter_values != '' THEN parameter_values END w_employee_id
        INTO w_employee_id
        FROM appauth_report_parameter
       WHERE     parameter_name = 'p_employee_id'
             AND report_name = p_report_name
             AND app_user_id = p_app_user_id;

      w_sql_stat :=
         'INSERT INTO appauth_report_table_tabular (report_column1,
                                          report_column2,
                                          report_column3,
                                          report_column4,
                                          report_column5,
                                          report_column6,
                                          report_column7,
                                          report_column8,
                                          report_column9,
                                          report_column10,
                                          report_column11,
                                          report_column12,
                                          report_column13,
                                          report_column14,
                                          report_column15,
                                          report_column16,
                                          report_column17,
                                          report_column18,
                                          report_column19,
                                          report_column20,
                                          report_column21,
                                          report_column22,
                                          report_column23,
                                          report_column24,
                                          report_column25,
                                          report_column26,
                                          report_column27,
                                          report_column28,
                                          report_column29,
                                          report_column30,
                                          report_column31,
                                          report_column32,
                                          report_column33,
                                          report_column34,
                                          report_column35,
                                          report_column36,
                                          report_column37,
                                          report_column38,
                                          report_column39,
                                          report_column40,
                                          report_column41,
                                          report_column42,
                                          report_column43,
                                          report_column44,
                                          report_column45,
                                          report_column46,
                                          app_user_id)
   WITH
      sales_details
      AS
         (SELECT s.branch_code,
                 m.center_code,
                 c.branch_center_code,
                 c.center_name,
                 s.invoice_number,
                 m.invoice_date,
                 s.client_id,
                 m.customer_name,
                 m.customer_phone,
                 m.employee_id,
                 m.total_quantity,
                 m.total_bill_amount,
                 m.bill_amount,
                 m.pay_amount,
                 m.due_amount,
                 m.advance_pay,
                 m.total_discount_amount,
                 s.product_id,s.serial_no,
                 p.product_name || ''('' || p.product_model || '')''
                    product_name,
                 s.quantity,
                 s.purchase_rate,
                 (s.purchase_rate * s.quantity)
                    total_purchase_value,
                 s.product_price
                    sales_rate,
                 s.returned_quantity,
                 s.total_price,
                 (CASE WHEN s.profit_amount > 0 THEN profit_amount ELSE 0 END)
                    profit_amount,
                 (CASE
                     WHEN s.profit_amount < 0 THEN abs (profit_amount)
                     ELSE 0
                  END)
                    loss_amount,
                 s.discount_rate,
                 s.discount_amount
            FROM sales_sales_details s,
                 sales_products p,
                 sales_sales_master m,
                 delar_center c
           WHERE     p.product_id = s.product_id
                 AND s.status <> ''C''
                 AND m.invoice_number = s.invoice_number
                 AND m.branch_code = s.branch_code
                 AND m.center_code = c.center_code ';

      IF w_from_date IS NOT NULL AND w_upto_date IS NOT NULL
      THEN
         w_sql_stat :=
               w_sql_stat
            || ' and m.invoice_date between '''
            || w_from_date
            || ''' and '''
            || w_upto_date
            || '''';
      END IF;

      IF w_branch_code IS NOT NULL
      THEN
         w_sql_stat := w_sql_stat || ' and m.branch_code = ' || w_branch_code;
      END IF;

      IF w_client_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and m.client_id = ''' || w_client_id || '''';
      END IF;

      IF w_employee_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and m.employee_id = ''' || w_employee_id || '''';
      END IF;

      IF w_ason_date IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and m.invoice_date = ''' || w_ason_date || '''';
      END IF;

      w_sql_stat :=
            w_sql_stat
         || '  ),
      sales_summary
      AS
         (  SELECT branch_code,
                   center_code,
                   branch_center_code,
                   center_name,
                   invoice_number,
                   invoice_date,
                   client_id,
                   customer_name,
                   customer_phone,
                   employee_id,
                   total_quantity,
                   total_bill_amount,
                   bill_amount,
                   pay_amount,
                   due_amount,
                   advance_pay,
                   total_discount_amount,
              count (product_id) OVER (PARTITION BY invoice_number)
                 item_count,
              sum (profit_amount) OVER (PARTITION BY invoice_number)
                 total_profit_amount,
              sum (loss_amount) OVER (PARTITION BY invoice_number)
                 total_loss_amount,
              product_id,
              serial_no,
              product_name,
              quantity,
              total_purchase_value,
              sales_rate,
              returned_quantity,
              total_price,
              profit_amount,
              loss_amount,
              discount_amount
              FROM sales_details),
      emi_setup
      AS
         (SELECT DISTINCT e.emi_reference_no,
                 e.emi_serial_number,
                 e.emi_down_amount,
                 e.total_emi_amount,
                 e.emi_inst_amount,
                 e.emi_inst_frequency,
                 e.emi_inst_repay_from_date,
                 e.number_of_installment,
                 e.installment_exp_date,
                 e.emi_rate,
                 e.emi_profit_amount,
                 e.emi_fee_amount,
                 e.emi_ins_rate,
                 e.emi_ins_fee_amount,
                 e.emi_doc_fee_amount
            FROM sales_emi_setup e, sales_summary s
           WHERE e.emi_reference_no=s.invoice_number 
           and emi_cancel_by IS NULL)
     SELECT s.branch_code,
            s.center_code,
            s.branch_center_code,
            s.center_name,
            s.invoice_number,
            to_char(s.invoice_date,''DD-MM-YYYY'') invoice_date,
            s.client_id,
         s.customer_name,
         s.customer_phone,
         s.employee_id,
         s.total_quantity,
         s.total_bill_amount,
         s.bill_amount,
         s.pay_amount,
         s.due_amount,
         s.advance_pay,
         s.total_discount_amount,
         s.item_count,
         (CASE WHEN s.serial_no = 1 THEN serial_no ELSE NULL END)
            rowspan,
         s.total_profit_amount,
         s.total_loss_amount,
         s.product_id,
         s.serial_no,
         s.product_name,
         s.quantity,
         s.total_purchase_value,
         s.sales_rate,
         s.returned_quantity,
         s.total_price,
         s.profit_amount,
         s.loss_amount,
         s.discount_amount,
         e.emi_serial_number,
         e.emi_down_amount,
         s.bill_amount+COALESCE (e.emi_profit_amount,0.00) total_emi_amount,
         e.emi_inst_amount,
         e.emi_inst_frequency,
            to_char(e.emi_inst_repay_from_date,''DD-MM-YYYY'') emi_inst_repay_from_date,
            e.number_of_installment,
            to_char(e.installment_exp_date,''DD-MM-YYYY'') installment_exp_date,
            e.emi_rate,
            e.emi_profit_amount,
            e.emi_fee_amount,
            e.emi_ins_rate,
            e.emi_ins_fee_amount,
            e.emi_doc_fee_amount, '''
         || p_app_user_id
         || '''
       FROM sales_summary s
            FULL OUTER JOIN emi_setup e ON (emi_reference_no = invoice_number)
   ORDER BY invoice_number';

      --RAISE EXCEPTION USING MESSAGE = w_sql_stat;

      EXECUTE w_sql_stat;
   END IF;

   o_status := 'S';
   o_errm := '';
EXCEPTION
   WHEN OTHERS
   THEN
      o_errm := SQLERRM;
      o_status := 'E';
END;
$$;


ALTER FUNCTION public.fn_run_sales_center_report(p_app_user_id character, p_report_name character, OUT o_status character, OUT o_errm character) OWNER TO postgres;

--
-- Name: fn_run_sales_customer_all_trandetails(character, character); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_run_sales_customer_all_trandetails(p_app_user_id character, p_center_code character, OUT o_status character, OUT o_errm character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   W_CLIENT_ID                 VARCHAR;
   W_CENTER_CODE               VARCHAR;
   W_CLIENT_NAME               VARCHAR;
   W_INVOICE_DATE              DATE;
   W_INVOICE_NUMBER            VARCHAR;
   W_PRODUCT_NAME              VARCHAR;
   W_PRODUCT_MODEL             VARCHAR;
   W_PRODUCT_QUANTITY          NUMERIC (22, 2) := 0;
   W_PRODUCT_PRICE             NUMERIC (22, 2) := 0;
   W_TOTAL_PRICE               NUMERIC (22, 2) := 0;
   W_PAY_AMOUNT                NUMERIC (22, 2) := 0;
   W_DUE_AMOUNT                NUMERIC (22, 2) := 0;
   W_INSTREPAY_REPAY_AMT       NUMERIC (22, 2) := 0;
   W_INSTREPAY_REPAY_FREQ      VARCHAR;
   W_NOF_INSTALLMENT           NUMERIC (22, 2) := 0;
   W_INSTREPAY_TOT_REPAY_AMT   NUMERIC (22, 2) := 0;
   W_DEPOSIT_DATE              DATE;
   W_DEPOSIT_AMOUNT            NUMERIC (22, 2) := 0;
   W_DEPOSIT_MEMO_NUM          VARCHAR;
   W_DPSRCV_DATE               DATE;
   W_DPSRCV_AMOUNT             NUMERIC (22, 2) := 0;
   W_DPSRCV_MEMO_NUM           VARCHAR;
   w_status                    VARCHAR := 'S';
   o_errm                      VARCHAR := '';
BEGIN
   DELETE FROM report_tran_detail
         WHERE app_user_id = p_app_user_id;

   INSERT INTO report_tran_detail
      (WITH
          CLIENT
          AS
             (SELECT ROW_NUMBER ()
                        OVER (PARTITION BY CLIENT_ID ORDER BY CLIENT_ID)
                        ROW_NUMBER,
                     CENTER_CODE,
                     CENTER_NAME,
                     CLIENT_ID,
                     CLIENT_NAME
                FROM SALES_CLIENTS, SALES_CNTREINFO_MODEL
               WHERE     CLIENT_CENTER_CODE = CENTER_CODE
                     AND CLIENT_CENTER_CODE = P_CENTER_CODE),
          SALES
          AS
             (  SELECT ROW_NUMBER ()
                          OVER (PARTITION BY CUSTOMER_ID ORDER BY CUSTOMER_ID)
                          ROW_NUMBER,
                       CUSTOMER_ID
                          CLIENT_ID,
                       CLIENT.CLIENT_NAME
                          CLIENT_NAME,
                       CLIENT_CENTER_CODE
                          CENTER_CODE,
                       CLIENT.CENTER_NAME
                          CENTER_NAME,
                       INVOICE_DATE,
                       INVOICE_NUMBER,
                       STRING_AGG (DISTINCT PRODUCT_NAME, ',')
                          PRODUCT_NAME,
                       STRING_AGG (DISTINCT PRODUCT_MODEL, ',')
                          PRODUCT_MODEL,
                       STRING_AGG (
                          TO_CHAR (COALESCE (PRODUCT_QUANTITY, 1), '9'),
                          ',')
                          PRODUCT_QUANTITY,
                       STRING_AGG (
                          TO_CHAR (COALESCE (PRODUCT_PRICE, 1), '99999'),
                          ',')
                          PRODUCT_PRICE,
                       (SELECT bill_amount
                          FROM SALES_SALES_MASTER m
                         WHERE m.invoice_number = g.INVOICE_NUMBER)
                          TOTAL_PRICE,
                       (SELECT PAY_AMOUNT
                          FROM SALES_SALES_MASTER m
                         WHERE m.invoice_number = g.INVOICE_NUMBER)
                          PAY_AMOUNT,
                       (SELECT DUE_AMOUNT
                          FROM SALES_SALES_MASTER m
                         WHERE m.invoice_number = g.INVOICE_NUMBER)
                          DUE_AMOUNT,
                       INSTREPAY_REPAY_AMT,
                       INSTREPAY_REPAY_FREQ,
                       NOF_INSTALLMENT,
                       INSTREPAY_TOT_REPAY_AMT
                  FROM (  SELECT CUSTOMER_ID,
                                 CLIENT_CENTER_CODE,
                                 CLIENT_NAME
                                    CLIENT_NAME,
                                 INVOICE_DATE,
                                 A.INVOICE_NUMBER,
                                 PRODUCT_NAME,
                                 PRODUCT_MODEL,
                                 QUANTITY
                                    PRODUCT_QUANTITY,
                                 PRODUCT_PRICE,
                                 PAY_AMOUNT
                                    PAY_AMOUNT,
                                 DUE_AMOUNT
                                    DUE_AMOUNT,
                                 (SELECT INSTREPAY_REPAY_AMT
                                    FROM SALES_EMISETUP_MODEL A
                                   WHERE A.SALES_INV_NUM = E.INVOICE_NUMBER)
                                    INSTREPAY_REPAY_AMT,
                                 (SELECT CASE
                                            WHEN TRIM (INSTREPAY_REPAY_FREQ) =
                                                 'W'
                                            THEN
                                               'WEEKLY'
                                            WHEN TRIM (INSTREPAY_REPAY_FREQ) =
                                                 'M'
                                            THEN
                                               'MONTHLY'
                                            ELSE
                                               'YEARLY'
                                         END
                                   FROM SALES_EMISETUP_MODEL A
                                  WHERE A.SALES_INV_NUM = E.INVOICE_NUMBER)
                                    INSTREPAY_REPAY_FREQ,
                                 (SELECT INSTREPAY_NUM_OF_INSTALLMENT
                                    FROM SALES_EMISETUP_MODEL A
                                   WHERE A.SALES_INV_NUM = E.INVOICE_NUMBER)
                                    NOF_INSTALLMENT,
                                 (SELECT INSTREPAY_TOT_REPAY_AMT
                                    FROM SALES_EMISETUP_MODEL A
                                   WHERE A.SALES_INV_NUM = E.INVOICE_NUMBER)
                                    INSTREPAY_TOT_REPAY_AMT
                            FROM SALES_PRODUCTS D,
                                 SALES_SALES_MASTER A,
                                 SALES_SALES_DETAILS E,
                                 SALES_CLIENTS B
                           WHERE     A.INVOICE_NUMBER = E.INVOICE_NUMBER
                                 --   AND SALES_TYPE = 'EMI'
                                 --    AND TRAN_TYPE = 'SL'
                                 AND A.CUSTOMER_ID = B.CLIENT_ID
                                 AND CLIENT_CENTER_CODE = P_CENTER_CODE
                                 AND E.PRODUCT_ID = D.PRODUCT_ID
                        ORDER BY E.PRODUCT_ID ASC,
                                 PRODUCT_NAME ASC,
                                 PRODUCT_MODEL ASC) G,
                       CLIENT
                 WHERE     G.CUSTOMER_ID = CLIENT.CLIENT_ID
                       AND G.CLIENT_CENTER_CODE = CLIENT.CENTER_CODE
              GROUP BY CUSTOMER_ID,
                       CLIENT_CENTER_CODE,
                       INVOICE_DATE,
                       INSTREPAY_REPAY_AMT,
                       INSTREPAY_REPAY_FREQ,
                       NOF_INSTALLMENT,
                       INSTREPAY_TOT_REPAY_AMT,
                       CLIENT.CLIENT_NAME,
                       CLIENT.CENTER_NAME,
                       INVOICE_NUMBER),
          EMI_RECEIVE
          AS
             (SELECT ROW_NUMBER ()
                     OVER (PARTITION BY SALES_EMIRCV_MODEL.CLIENT_ID
                           ORDER BY SALES_EMIRCV_MODEL.CLIENT_ID) ROW_NUMBER,
                     SALES_EMIRCV_MODEL.CENTER_CODE,
                     CLIENT.CENTER_NAME CENTER_NAME,
                     SALES_EMIRCV_MODEL.CLIENT_ID CLIENT_ID,
                     CLIENT.CLIENT_NAME CLIENT_NAME,
                     INSTRCV_INV_NUMBER,
                     INSTRCV_ENTRY_DATE,
                     INSTRCV_INSTLMNT,
                     INSTRCV_REF_NUM
                FROM SALES_EMIRCV_MODEL, CLIENT
               WHERE     SALES_EMIRCV_MODEL.CENTER_CODE = P_CENTER_CODE
                     AND CLIENT.CENTER_CODE = SALES_EMIRCV_MODEL.CENTER_CODE
                     AND SALES_EMIRCV_MODEL.CLIENT_ID = CLIENT.CLIENT_ID),
          DEPRCV
          AS
             (SELECT ROW_NUMBER ()
                     OVER (PARTITION BY SALES_DEPRCV_MODEL.CLIENT_ID
                           ORDER BY SALES_DEPRCV_MODEL.CLIENT_ID) ROW_NUMBER,
                     SALES_DEPRCV_MODEL.CENTER_CODE CENTER_CODE,
                     CLIENT.CENTER_NAME CENTER_NAME,
                     SALES_DEPRCV_MODEL.CLIENT_ID CLIENT_ID,
                     CLIENT.CLIENT_NAME CLIENT_NAME,
                     DEPOSIT_DATE,
                     DEPOSIT_AMOUNT,
                     DEPOSIT_MEMO_NUM
                FROM SALES_DEPRCV_MODEL, CLIENT
               WHERE     SALES_DEPRCV_MODEL.CENTER_CODE = P_CENTER_CODE
                     AND CLIENT.CENTER_CODE = SALES_DEPRCV_MODEL.CENTER_CODE
                     AND SALES_DEPRCV_MODEL.CLIENT_ID = CLIENT.CLIENT_ID),
          DPSRCV
          AS
             (SELECT ROW_NUMBER ()
                     OVER (PARTITION BY SALES_DPS_RECEIVE.CLIENT_ID
                           ORDER BY SALES_DPS_RECEIVE.CLIENT_ID) ROW_NUMBER,
                     SALES_DPS_RECEIVE.CENTER_CODE CENTER_CODE,
                     SALES_DPS_RECEIVE.CLIENT_ID CLIENT_ID,
                     CLIENT.CENTER_NAME CENTER_NAME,
                     CLIENT.CLIENT_NAME CLIENT_NAME,
                     DPSRCV_DATE,
                     DPSRCV_AMOUNT,
                     DPSRCV_MEMO_NUM
                FROM SALES_DPS_RECEIVE, CLIENT
               WHERE     SALES_DPS_RECEIVE.CENTER_CODE = P_CENTER_CODE
                     AND CLIENT.CENTER_CODE = SALES_DPS_RECEIVE.CENTER_CODE
                     AND SALES_DPS_RECEIVE.CLIENT_ID = CLIENT.CLIENT_ID)
       SELECT COALESCE (CLIENT.CENTER_CODE,
                        SALES.CENTER_CODE,
                        EMI_RECEIVE.CENTER_CODE,
                        DPSRCV.CENTER_CODE,
                        DEPRCV.CENTER_CODE) CENTER_CODE,
              COALESCE (CLIENT.CENTER_NAME,
                        SALES.CENTER_NAME,
                        EMI_RECEIVE.CENTER_NAME,
                        DPSRCV.CENTER_NAME,
                        DEPRCV.CENTER_NAME) CENTER_NAME,
              COALESCE (CLIENT.CLIENT_ID,
                        SALES.CLIENT_ID,
                        EMI_RECEIVE.CLIENT_ID,
                        DPSRCV.CLIENT_ID,
                        DEPRCV.CLIENT_ID) CLIENT_ID,
              COALESCE (CLIENT.CLIENT_NAME,
                        SALES.CLIENT_NAME,
                        EMI_RECEIVE.CLIENT_NAME,
                        DPSRCV.CLIENT_NAME,
                        DEPRCV.CLIENT_NAME) CLIENT_NAME,
              INVOICE_DATE,
              COALESCE (INVOICE_NUMBER, ''),
              COALESCE (PRODUCT_NAME, ''),
              COALESCE (PRODUCT_MODEL, ''),
              COALESCE (PRODUCT_QUANTITY, ''),
              COALESCE (PRODUCT_PRICE, ''),
              COALESCE (TOTAL_PRICE, 0.00),
              COALESCE (PAY_AMOUNT, 0.00),
              COALESCE (DUE_AMOUNT, 0.00),
              COALESCE (INSTREPAY_REPAY_AMT, 0),
              COALESCE (INSTREPAY_REPAY_FREQ, ''),
              COALESCE (NOF_INSTALLMENT, 0),
              COALESCE (INSTREPAY_TOT_REPAY_AMT, 0),
              COALESCE (INSTRCV_INV_NUMBER, ''),
              INSTRCV_ENTRY_DATE,
              COALESCE (INSTRCV_INSTLMNT, 0),
              COALESCE (INSTRCV_REF_NUM, ''),
              DEPOSIT_DATE,
              COALESCE (DEPOSIT_AMOUNT, 0),
              COALESCE (DEPOSIT_MEMO_NUM, ''),
              DPSRCV_DATE,
              COALESCE (DPSRCV_AMOUNT, 0),
              COALESCE (DPSRCV_MEMO_NUM, ''),
              COALESCE (P_APP_USER_ID, ''),
              current_date
         FROM CLIENT
              FULL OUTER JOIN SALES
                 ON (    CLIENT.CENTER_CODE = SALES.CENTER_CODE
                     AND CLIENT.CLIENT_ID = SALES.CLIENT_ID
                     AND CLIENT.ROW_NUMBER = SALES.ROW_NUMBER)
              FULL OUTER JOIN EMI_RECEIVE
                 ON (    EMI_RECEIVE.CENTER_CODE = CLIENT.CENTER_CODE
                     AND EMI_RECEIVE.CLIENT_ID = CLIENT.CLIENT_ID
                     AND EMI_RECEIVE.ROW_NUMBER = CLIENT.ROW_NUMBER)
              FULL OUTER JOIN DPSRCV
                 ON (    DPSRCV.CENTER_CODE = CLIENT.CENTER_CODE
                     AND DPSRCV.CLIENT_ID = CLIENT.CLIENT_ID
                     AND DPSRCV.ROW_NUMBER = CLIENT.ROW_NUMBER)
              FULL OUTER JOIN DEPRCV
                 ON (    DEPRCV.CENTER_CODE = CLIENT.CENTER_CODE
                     AND DEPRCV.CLIENT_ID = CLIENT.CLIENT_ID
                     AND DEPRCV.ROW_NUMBER = CLIENT.ROW_NUMBER));

   o_status := 'S';
   o_errm := '';
EXCEPTION
   WHEN OTHERS
   THEN
      IF w_status = 'E'
      THEN
         o_status := w_status;
         o_errm := w_errm;
      ELSE
         o_status := 'E';
         o_errm := SQLERRM;
      END IF;
END;
$$;


ALTER FUNCTION public.fn_run_sales_customer_all_trandetails(p_app_user_id character, p_center_code character, OUT o_status character, OUT o_errm character) OWNER TO postgres;

--
-- Name: fn_run_sales_report(character, character); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_run_sales_report(p_app_user_id character, p_report_name character, OUT o_status character, OUT o_errm character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_status                 VARCHAR;
   w_errm                   VARCHAR;
   w_sql_stat               TEXT := '';
   w_center_code            VARCHAR;
   w_from_date              DATE;
   w_upto_date              DATE;
   w_ason_date              DATE;
   w_current_business_day   DATE;
   w_ledger_code            VARCHAR;
   w_invoice_number         VARCHAR;
   w_user_id                VARCHAR;
   w_acc_type_code          VARCHAR;
   w_employee_id            VARCHAR;
   w_client_id              VARCHAR;
   w_supplier_id            VARCHAR;
   w_account_number         VARCHAR;
   w_account_title          VARCHAR;
   w_product_id             VARCHAR;
   w_branch_code            INTEGER;
   w_zero_balance           VARCHAR := 'N';
   w_transfer_tran          VARCHAR := 'N';
   w_closing_balance        NUMERIC (22, 2);
   w_opening_balance        NUMERIC (22, 2);
   w_cash_gl_code           VARCHAR;
   rec_delar_list           RECORD;
   rec_branch_list          RECORD;
   rec_product_list         RECORD;
   w_branch_name            VARCHAR;
   w_branch_address         VARCHAR;
   w_group_id               VARCHAR;
   w_brand_id               VARCHAR;
   w_sales_report_type      VARCHAR;
BEGIN
   DELETE FROM appauth_report_table_tabular
         WHERE app_user_id = p_app_user_id;

   SELECT CASE WHEN parameter_values != '' THEN parameter_values END
    INTO w_center_code
    FROM appauth_report_parameter
   WHERE     parameter_name = 'p_center_code'
         AND report_name = p_report_name
         AND app_user_id = p_app_user_id;

   SELECT CASE
             WHEN parameter_values != ''
             THEN
                cast (parameter_values AS INTEGER)
          END w_branch_code
     INTO w_branch_code
     FROM appauth_report_parameter
    WHERE     parameter_name = 'p_branch_code'
          AND report_name = p_report_name
          AND app_user_id = p_app_user_id;

   SELECT CASE WHEN parameter_values != '' THEN parameter_values END w_group_id
     INTO w_group_id
     FROM appauth_report_parameter
    WHERE     parameter_name = 'p_group_id'
          AND report_name = p_report_name
          AND app_user_id = p_app_user_id;

   SELECT CASE WHEN parameter_values != '' THEN parameter_values END w_group_id
     INTO w_brand_id
     FROM appauth_report_parameter
    WHERE     parameter_name = 'p_brand_id'
          AND report_name = p_report_name
          AND app_user_id = p_app_user_id;

   SELECT CASE
             WHEN parameter_values != '' THEN cast (parameter_values AS DATE)
          END p_from_date
     INTO w_from_date
     FROM appauth_report_parameter
    WHERE     parameter_name = 'p_from_date'
          AND report_name = p_report_name
          AND app_user_id = p_app_user_id;

   SELECT CASE
             WHEN parameter_values != '' THEN cast (parameter_values AS DATE)
          END p_upto_date
     INTO w_upto_date
     FROM appauth_report_parameter
    WHERE     parameter_name = 'p_upto_date'
          AND report_name = p_report_name
          AND app_user_id = p_app_user_id;

   SELECT CASE
             WHEN parameter_values != '' THEN cast (parameter_values AS DATE)
          END p_ason_date
     INTO w_ason_date
     FROM appauth_report_parameter
    WHERE     parameter_name = 'p_ason_date'
          AND report_name = p_report_name
          AND app_user_id = p_app_user_id;

   IF w_from_date = w_upto_date AND w_ason_date IS NULL
   THEN
      w_ason_date := w_upto_date;
   END IF;

   IF p_report_name = 'sales_invoice'
   THEN
      SELECT parameter_values p_invoice_number
        INTO w_invoice_number
        FROM appauth_report_parameter
       WHERE     parameter_name = 'p_invoice_number'
             AND report_name = p_report_name
             AND app_user_id = p_app_user_id;

      w_sql_stat :=
         'INSERT INTO appauth_report_table_tabular (report_column1,
                                        report_column2,
                                        report_column3,
                                        report_column4,
                                        report_column5,
                                        report_column6,
                                        report_column7,
                                        report_column8,
                                        report_column9,
                                        app_user_id)
   SELECT ROW_NUMBER () OVER (ORDER BY d.app_data_time) ROW_NUMBER,
          p.product_name||'' (''||COALESCE (p.product_model, '''')||'')'',
          p.product_model,
          d.quantity,
          d.product_price,
          m.total_discount_amount,
          m.employee_id executive_phone,
          d.quantity * d.product_price total_amount,
          invoice_comments,
         ''' || p_app_user_id || '''
     FROM sales_sales_master m, sales_sales_details d, sales_products p
    WHERE     m.invoice_number = d.invoice_number
          AND p.product_id = d.product_id ';

      IF w_invoice_number IS NOT NULL
      THEN
         w_sql_stat :=
               w_sql_stat
            || ' and m.invoice_number = '''
            || w_invoice_number
            || '''';
      END IF;

      --RAISE EXCEPTION USING MESSAGE = w_sql_stat;

      EXECUTE w_sql_stat;
   ELSIF p_report_name = 'sales_and_return_details'
   THEN
      SELECT CASE WHEN parameter_values != '' THEN parameter_values END w_account_number
        INTO w_account_number
        FROM appauth_report_parameter
       WHERE     parameter_name = 'p_account_number'
             AND report_name = p_report_name
             AND app_user_id = p_app_user_id;

      IF w_account_number IS NOT NULL
      THEN
         SELECT DISTINCT client_id, account_title
           INTO w_client_id, w_account_title
           FROM finance_accounts_balance
          WHERE account_number = w_account_number;
      END IF;

      SELECT CASE WHEN parameter_values != '' THEN parameter_values END w_product_id
        INTO w_product_id
        FROM appauth_report_parameter
       WHERE     parameter_name = 'p_product_id'
             AND report_name = p_report_name
             AND app_user_id = p_app_user_id;

      w_sql_stat :=
            'INSERT INTO appauth_report_table_tabular (report_column1,
                                        report_column2,
                                        report_column3,
                                        report_column4,
                                        report_column5,
                                        report_column6,
                                        report_column7,
                                        report_column8,
                                        report_column9,
                                        report_column10,
                                        report_column11,
                                        report_column12,
                                        report_column13,
                                        report_column14,
                                        report_column15,
                                        app_user_id)
  SELECT c.client_id,
         c.client_name,
         product_id,
         product_name,
         transaction_date,
         sales_quantity,
         sales_rate,
         sales_total_price,
         sales_discount_amount,
         sales_net_price,
         returned_quantity,
         return_rate,
         return_total_price,
         (case when (ROW_NUMBER ()
         OVER (PARTITION BY c.client_id, transaction_date
               ORDER BY c.client_name, transaction_date, product_name, row_serial_id))=1 then ''1'' else '''' end)
            row_serial,
         count (c.client_id) OVER (PARTITION BY c.client_id, transaction_date)
            total_row,
         '''
         || p_app_user_id
         || '''
    FROM (SELECT COALESCE (s.client_id, r.client_id) client_id,
                 COALESCE (s.product_id, r.product_id) product_id,
                    COALESCE (s.product_name, r.product_name)
                 || ''(''
                 || COALESCE (s.product_model, r.product_model, '' '')
                 || '')'' product_name,
                 COALESCE (s.invoice_date, r.return_date) transaction_date,
                 COALESCE (s.quantity, 0) sales_quantity,
                 COALESCE (s.unit_price, 0) sales_rate,
                 COALESCE (s.total_price, 0) sales_total_price,
                 COALESCE (s.discount_amount, 0) sales_discount_amount,
                 COALESCE (s.net_price, 0) sales_net_price,
                 COALESCE (r.returned_quantity, 0) returned_quantity,
                 COALESCE (r.unit_price, 0) return_rate,
                 COALESCE (r.net_price, 0) return_total_price,
                 s.row_serial_id
            FROM (SELECT d.client_id,
                         p.product_id,
                         m.invoice_date,
                         p.product_model,
                         p.product_name,
                         d.quantity,
                         d.product_price unit_price,
                         d.total_price,
                         d.discount_amount,
                         (d.total_price - d.discount_amount) net_price,
                         d.id row_serial_id
                    FROM sales_sales_details d,
                         sales_products p,
                         sales_sales_master m
                   WHERE     d.product_id = p.product_id
                         AND d.invoice_number = m.invoice_number ';

      IF w_from_date IS NOT NULL AND w_upto_date IS NOT NULL
      THEN
         w_sql_stat :=
               w_sql_stat
            || ' and m.invoice_date between '''
            || w_from_date
            || ''' and '''
            || w_upto_date
            || '''';
      END IF;

      IF w_branch_code IS NOT NULL
      THEN
         w_sql_stat := w_sql_stat || ' and m.branch_code = ' || w_branch_code;
      END IF;

      IF w_product_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and d.product_id = ''' || w_product_id || '''';
      END IF;

      IF w_group_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and p.product_group = ''' || w_group_id || '''';
      END IF;

      IF w_brand_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and p.brand_id = ''' || w_brand_id || '''';
      END IF;

      IF w_client_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and d.client_id = ''' || w_client_id || '''';
      END IF;

      IF w_ason_date IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and m.invoice_date = ''' || w_ason_date || '''';
      END IF;


      w_sql_stat :=
            w_sql_stat
         || '   ) s
                 FULL OUTER JOIN
                 (SELECT d.client_id,
                         p.product_id,
                         d.return_date,
                         p.product_model,
                         p.product_name,
                         d.returned_quantity,
                         round((d.return_amount / d.returned_quantity),0) unit_price,
                         d.return_amount net_price
                    FROM sales_sales_return_details d, sales_products p
                   WHERE d.product_id = p.product_id ';

      IF w_from_date IS NOT NULL AND w_upto_date IS NOT NULL
      THEN
         w_sql_stat :=
               w_sql_stat
            || ' and d.return_date between '''
            || w_from_date
            || ''' and '''
            || w_upto_date
            || '''';
      END IF;

      IF w_branch_code IS NOT NULL
      THEN
         w_sql_stat := w_sql_stat || ' and d.branch_code = ' || w_branch_code;
      END IF;

      IF w_product_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and d.product_id = ''' || w_product_id || '''';
      END IF;

      IF w_group_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and p.product_group = ''' || w_group_id || '''';
      END IF;

      IF w_brand_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and p.brand_id = ''' || w_brand_id || '''';
      END IF;

      IF w_client_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and d.client_id = ''' || w_client_id || '''';
      END IF;


      IF w_ason_date IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and d.return_date = ''' || w_ason_date || '''';
      END IF;

      w_sql_stat := w_sql_stat || '    ) r
                    ON (    s.client_id = r.client_id
                        AND s.product_id = r.product_id
                        AND s.invoice_date = r.return_date)) s,
         sales_clients c
   WHERE s.client_id = c.client_id
ORDER BY c.client_name, transaction_date, product_name, row_serial_id';

      ---RAISE EXCEPTION USING MESSAGE = w_sql_stat;

      EXECUTE w_sql_stat;
   ELSIF p_report_name = 'sales_and_return_statement'
   THEN
      SELECT CASE WHEN parameter_values != '' THEN parameter_values END w_account_number
        INTO w_account_number
        FROM appauth_report_parameter
       WHERE     parameter_name = 'p_account_number'
             AND report_name = p_report_name
             AND app_user_id = p_app_user_id;

      IF w_account_number IS NOT NULL
      THEN
         SELECT DISTINCT client_id, account_title
           INTO w_client_id, w_account_title
           FROM finance_accounts_balance
          WHERE account_number = w_account_number;
      END IF;

      SELECT CASE WHEN parameter_values != '' THEN parameter_values END w_account_number
        INTO w_product_id
        FROM appauth_report_parameter
       WHERE     parameter_name = 'p_product_id'
             AND report_name = p_report_name
             AND app_user_id = p_app_user_id;

      SELECT w_status, w_errm
        INTO w_status, w_errm
        FROM fn_finance_acbal_hist (w_account_number, w_from_date);

      BEGIN
         INSERT INTO appauth_report_parameter (app_user_id,
                                               report_name,
                                               parameter_name,
                                               parameter_values)
              VALUES (p_app_user_id,
                      p_report_name,
                      'p_customer_name',
                      w_account_title);
      END;

      w_sql_stat :=
                      'INSERT INTO appauth_report_table_tabular (report_column1,
                                        report_column2,
                                        report_column3,
                                        report_column4,
                                        report_column5,
                                        report_column6,
                                        report_column7,
                                        report_column8,
                                        report_column9,
                                        report_column10,
                                        report_column11,
                                        report_column12,
                                        report_column13,
                                        report_column14,
                                        report_column15,
                                        report_column16,
                                        report_column17,
                                        report_column18,
                                        app_user_id)
     SELECT '''
                   || w_client_id
                   || ''',
            '''
                   || w_account_title
                   || ''',
            product_id,
            product_name,
            transaction_date,
            COALESCE (sales_quantity,0) sales_quantity,
            COALESCE (sales_rate,0.00) sales_rate,
            COALESCE (sales_total_price,0.00) sales_total_price,
            COALESCE (sales_discount_amount,0.00) sales_discount_amount,
            COALESCE (sales_net_price,0.00) sales_net_price,
            COALESCE (returned_quantity,0) returned_quantity,
            COALESCE (return_rate,0.00) return_rate,
            COALESCE (return_total_price,0.00) return_total_price,
            row_serial,total_row,
            (CASE WHEN row_serial=''1'' THEN credit_balance ELSE 0 END) credit_balance,
            (CASE WHEN row_serial=''1'' THEN debit_balance ELSE 0 END) debit_balance,
            account_balance,
            app_user_id
            FROM (
     SELECT product_id,
            COALESCE (product_name,transaction_narration) product_name,
            transaction_date,transaction_narration,
            sales_quantity,
            sales_rate,
            sales_total_price,
            sales_discount_amount,
            sales_net_price,
            returned_quantity,
            return_rate,
            return_total_price,
            (CASE
                WHEN (ROW_NUMBER ()
                      OVER (
                         PARTITION BY transaction_date
                         ORDER BY transaction_date, product_name)) =
                     1
                THEN
                   ''1''
                ELSE
                   ''''
             END) row_serial,
            count (transaction_date)
               OVER (PARTITION BY transaction_date) total_row,
            credit_balance,
            debit_balance,
            account_balance,
         '''
                   || p_app_user_id
                   || ''' app_user_id
       FROM (SELECT client_id,
                    product_id,
                    product_name,
                    COALESCE (s.transaction_date, t.transaction_date)
                       transaction_date,transaction_narration,
                    sales_quantity,
                    sales_rate,
                    sales_total_price,
                    sales_discount_amount,
                    sales_net_price,
                    returned_quantity,
                    return_rate,
                    return_total_price,
                    credit_balance,
                    debit_balance,
                    account_balance
               FROM (SELECT COALESCE (s.client_id, r.client_id)
                               client_id,
                            COALESCE (s.product_id, r.product_id)
                               product_id,
                               COALESCE (s.product_name, r.product_name)
                            || ''(''
                            || COALESCE (s.product_model, r.product_model, '' '')
                            || '')''
                               product_name,
                            COALESCE (s.invoice_date, r.return_date)
                               transaction_date,
                            COALESCE (s.quantity, 0)
                               sales_quantity,
                            COALESCE (s.unit_price, 0)
                               sales_rate,
                            COALESCE (s.total_price, 0)
                               sales_total_price,
                            COALESCE (s.discount_amount, 0)
                               sales_discount_amount,
                            COALESCE (s.net_price, 0)
                               sales_net_price,
                            COALESCE (r.returned_quantity, 0)
                               returned_quantity,
                            COALESCE (r.unit_price, 0)
                               return_rate,
                            COALESCE (r.net_price, 0)
                               return_total_price
                       FROM (SELECT d.client_id,
                                    p.product_id,
                                    m.invoice_date,
                                    p.product_model,
                                    p.product_name,
                                    d.quantity,
                                    d.product_price unit_price,
                                    d.total_price,
                                    d.discount_amount,
                                    (d.total_price - d.discount_amount) net_price
                               FROM sales_sales_details d,
                                    sales_products p,
                                    sales_sales_master m
                              WHERE     d.product_id = p.product_id
                                    AND d.invoice_number = m.invoice_number
                                    and m.status<>''C'' 
                                    and d.client_id='''
                   || w_client_id
                   || ''' and m.invoice_date between '''
                   || w_from_date
                   || ''' and '''
                   || w_upto_date
                   || ''') s
                            FULL OUTER JOIN
                            (SELECT d.client_id,
                                    p.product_id,
                                    d.return_date,
                                    p.product_model,
                                    p.product_name,
                                    d.returned_quantity,
                                    round (
                                       (d.return_amount / d.returned_quantity),
                                       0) unit_price,
                                    d.return_amount net_price
                               FROM sales_sales_return_details d,
                                    sales_products p
                              WHERE d.product_id = p.product_id and d.client_id='''
                   || w_client_id
                   || ''' and d.return_date between '''
                   || w_from_date
                   || ''' and '''
                   || w_upto_date
                   || ''') r
                               ON (    s.client_id = r.client_id
                                   AND s.product_id = r.product_id
                                   AND s.invoice_date = r.return_date)) S
                    FULL OUTER JOIN
                    (SELECT transaction_date,transaction_narration,
                            credit_balance,
                            debit_balance,
                            SUM (credit_balance - debit_balance)
                               OVER (ORDER BY serial_number) account_balance
                       FROM (SELECT 1  serial_number,
                                    '''
                   || w_from_date
                 - 1
              || ''' transaction_date,''Opening Balance'' transaction_narration,
                                    (CASE
                                        WHEN o_account_balance > 0
                                        THEN
                                           o_account_balance
                                        ELSE
                                           0
                                     END) credit_balance,
                                    (CASE
                                        WHEN o_account_balance < 0
                                        THEN
                                           abs (o_account_balance)
                                        ELSE
                                           0
                                     END) debit_balance
                               FROM fn_finance_get_ason_acbal ('''
              || w_account_number
              || ''', '''
              || w_from_date
            - 1
         || ''')
                             UNION ALL
                               SELECT   (ROW_NUMBER ()
                                            OVER (ORDER BY transaction_date))
                                      + 1 serial_number,
                                      transaction_date,STRING_AGG (transaction_narration, '','') transaction_narration,
                                      sum (credit_balance) credit_balance,
                                      sum (debit_balance) debit_balance
                                 FROM (SELECT transaction_date,
                                              transaction_narration,
                                              (CASE
                                                  WHEN tran_debit_credit = ''C''
                                                  THEN
                                                     tran_amount
                                                  ELSE
                                                     0
                                               END) credit_balance,
                                              (CASE
                                                  WHEN tran_debit_credit = ''D''
                                                  THEN
                                                     tran_amount
                                                  ELSE
                                                     0
                                               END) debit_balance
                                         FROM finance_transaction_details
                                        WHERE     account_number =
                                                  '''
         || w_account_number
         || '''
                                              AND cancel_by IS NULL
                                              AND transaction_date BETWEEN '''
         || w_from_date
         || '''
                                                                       AND   '''
         || w_upto_date
         || ''') t
                             GROUP BY transaction_date) a
                      WHERE serial_number >= 1) T
                       ON (T.transaction_date = S.transaction_date)) s
   ORDER BY transaction_date, product_name) T';

      ---RAISE EXCEPTION USING MESSAGE = w_sql_stat;

      EXECUTE w_sql_stat;
   ELSIF p_report_name = 'sales_daywisesales'
   THEN
      SELECT CASE WHEN parameter_values != '' THEN parameter_values END
       INTO w_product_id
       FROM appauth_report_parameter
      WHERE     parameter_name = 'p_product_id'
            AND report_name = p_report_name
            AND app_user_id = p_app_user_id;


      w_sql_stat :=
         'INSERT INTO appauth_report_table_tabular (report_column1,
                                        report_column2,
                                        report_column3,
                                        report_column4,
                                        report_column5,
                                        report_column6,
                                        report_column7,
                                        report_column8,
                                        report_column9,
                                        report_column10,
                                        app_user_id)
   SELECT ROW_NUMBER () OVER (ORDER BY m.invoice_date, p.product_name)
             ROW_NUMBER,
          d.product_id,
          TO_CHAR(m.invoice_date ,''mm/dd/yyyy''),
          p.product_name,
          p.product_model,
          g.group_name,
          d.product_price,
          d.quantity,
          d.total_price,
          d.discount_amount, ''' || p_app_user_id || '''
     FROM sales_products p,
          sales_sales_master m,
          sales_sales_details d,
          sales_products_group g
    WHERE     m.invoice_number = d.invoice_number
          AND p.product_id = d.product_id
          AND g.group_id = p.product_group ';

      IF w_from_date IS NOT NULL AND w_upto_date IS NOT NULL
      THEN
         w_sql_stat :=
               w_sql_stat
            || ' and m.invoice_date between '''
            || w_from_date
            || ''' and '''
            || w_upto_date
            || '''';
      END IF;

      IF w_branch_code IS NOT NULL
      THEN
         w_sql_stat := w_sql_stat || ' and m.branch_code = ' || w_branch_code;
      END IF;

      IF w_group_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and g.group_id = ''' || w_group_id || '''';
      END IF;

      IF w_product_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and p.product_id = ''' || w_product_id || '''';
      END IF;

      IF w_group_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and p.product_group = ''' || w_group_id || '''';
      END IF;

      IF w_brand_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and p.brand_id = ''' || w_brand_id || '''';
      END IF;

      IF w_ason_date IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and m.invoice_date = ''' || w_ason_date || '''';
      END IF;

      w_sql_stat := w_sql_stat || ' order by m.invoice_date, p.product_name';

      --RAISE EXCEPTION USING MESSAGE = w_sql_stat;
      EXECUTE w_sql_stat;
   ELSIF p_report_name = 'sales_details_report'
   THEN
      SELECT CASE WHEN parameter_values != '' THEN parameter_values END p_invoice_number
        INTO w_invoice_number
        FROM appauth_report_parameter
       WHERE     parameter_name = 'p_invoice_number'
             AND report_name = p_report_name
             AND app_user_id = p_app_user_id;

      SELECT CASE WHEN parameter_values != '' THEN parameter_values END sales_summary_type
        INTO w_sales_report_type
        FROM appauth_report_parameter
       WHERE     parameter_name = 'p_sales_report_type'
             AND report_name = p_report_name
             AND app_user_id = p_app_user_id;

      SELECT CASE WHEN parameter_values != '' THEN parameter_values END w_account_number
        INTO w_account_number
        FROM appauth_report_parameter
       WHERE     parameter_name = 'p_account_number'
             AND report_name = p_report_name
             AND app_user_id = p_app_user_id;

      IF w_account_number IS NOT NULL
      THEN
         SELECT DISTINCT client_id, account_title
           INTO w_client_id, w_account_title
           FROM finance_accounts_balance
          WHERE account_number = w_account_number;
      END IF;

      SELECT CASE WHEN parameter_values != '' THEN parameter_values END product_id
        INTO w_product_id
        FROM appauth_report_parameter
       WHERE     parameter_name = 'p_product_id'
             AND report_name = p_report_name
             AND app_user_id = p_app_user_id;

      w_sql_stat :=
         'INSERT INTO appauth_report_table_tabular (report_column1,
                                          report_column2,
                                          report_column3,
                                          report_column4,
                                          report_column5,
                                          report_column6,
                                          report_column7,
                                          report_column8,
                                          report_column9,
                                          report_column10,
                                          app_user_id)
   WITH
      sales_details
      AS
         (SELECT s.branch_code,
                 s.center_code,
                 s.invoice_number,
                 m.invoice_date,
                 s.client_id,
                 m.customer_name,
                 s.product_id,
                 p.product_name || ''('' || p.product_model || '')''
                    product_name,
                 s.purchase_rate,
                 (s.purchase_rate*s.quantity) total_purchase_value,
                 s.product_price,
                 s.quantity,
                 s.returned_quantity,
                 s.total_price,
                 (CASE WHEN s.profit_amount > 0 THEN profit_amount ELSE 0 END)
                    profit_amount,
                 (CASE
                     WHEN s.profit_amount < 0 THEN abs (profit_amount)
                     ELSE 0
                  END)
                    loss_amount,
                 s.discount_rate,
                 s.discount_amount,
                 s.status
            FROM sales_sales_details s,
                 sales_products p,
                 sales_sales_master m
           WHERE     p.product_id = s.product_id
                 AND s.status <> ''C''
                 AND m.invoice_number = s.invoice_number
                 AND m.branch_code = s.branch_code ';

      IF w_invoice_number IS NOT NULL
      THEN
         w_sql_stat :=
               w_sql_stat
            || ' and m.invoice_number = '''
            || w_invoice_number
            || '''';
      END IF;

      IF w_branch_code IS NOT NULL
      THEN
         w_sql_stat := w_sql_stat || ' and m.branch_code = ' || w_branch_code;
      END IF;

      IF w_center_code IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and s.center_code = ''' || w_center_code || '''';
      END IF;

      IF w_product_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and s.product_id = ''' || w_product_id || '''';
      END IF;

      IF w_group_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and p.product_group = ''' || w_group_id || '''';
      END IF;

      IF w_brand_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and p.brand_id = ''' || w_brand_id || '''';
      END IF;

      IF w_client_id IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and s.client_id = ''' || w_client_id || '''';
      END IF;

      IF w_ason_date IS NOT NULL
      THEN
         w_sql_stat :=
            w_sql_stat || ' and m.invoice_date = ''' || w_ason_date || '''';
      END IF;

      IF w_from_date IS NOT NULL AND w_upto_date IS NOT NULL
      THEN
         w_sql_stat :=
               w_sql_stat
            || ' and m.invoice_date between '''
            || w_from_date
            || ''' and '''
            || w_upto_date
            || '''';
      END IF;

      IF w_sales_report_type = 'PR'
      THEN
         -- Product wise profit and loss
         w_sql_stat := w_sql_stat || ' )
     SELECT product_name,
			sum(total_purchase_value) total_purchase_value,
			sum(product_price) sales_price,
			sum(quantity) quantity,
			sum(returned_quantity) returned_quantity ,
			sum(total_price) total_price,
			sum(discount_amount) discount_amount,
            sum (purchase_rate) profit_amount,
            sum (loss_amount) loss_amount,
            sum (profit_amount - loss_amount) net_profit_loss,
             ''' || p_app_user_id || ''' app_user_id
       FROM sales_details
   GROUP BY product_name
   ORDER BY product_name ';
      ELSIF w_sales_report_type = 'DT'
      THEN
         -- Product wise profit and loss
         w_sql_stat := w_sql_stat || ' )
     SELECT TO_CHAR(invoice_date,''DD-MM-YYYY''),
			sum(total_purchase_value) total_purchase_value,
			sum(product_price) sales_price,
			sum(quantity) quantity,
			sum(returned_quantity) returned_quantity,
			sum(total_price) total_price,
			sum(discount_amount) discount_amount,
            sum (profit_amount) profit_amount,
            sum (loss_amount) loss_amount,
            sum (profit_amount - loss_amount) net_profit_loss,
             ''' || p_app_user_id || ''' app_user_id
       FROM sales_details
   GROUP BY invoice_date
   ORDER BY invoice_date ';
      ELSIF w_sales_report_type = 'CS'
      THEN
         -- Product wise profit and loss
         w_sql_stat := w_sql_stat || ' )
     SELECT customer_name,
			sum(total_purchase_value) total_purchase_value,
			sum(product_price) sales_price,
			sum(quantity) quantity,
			sum(returned_quantity) returned_quantity,
			sum(total_price) total_price,
			sum(discount_amount) discount_amount,
            sum (profit_amount) profit_amount,
            sum (loss_amount) loss_amount,
            sum (profit_amount - loss_amount) net_profit_loss,
             ''' || p_app_user_id || ''' app_user_id
       FROM sales_details
   GROUP BY customer_name
   ORDER BY customer_name ';
      ELSIF w_sales_report_type = 'BR'
      THEN
         -- Product wise profit and loss
         w_sql_stat :=
               w_sql_stat
            || ' )
     SELECT (SELECT branch_name from appauth_branch b where b.branch_code=s.branch_code),
			sum(total_purchase_value) total_purchase_value,
			sum(product_price) sales_price,
			sum(quantity) quantity,
			sum(returned_quantity) returned_quantity,
			sum(total_price) total_price,
			sum(discount_amount) discount_amount,
            sum (profit_amount) profit_amount,
            sum (loss_amount) loss_amount,
            sum (profit_amount - loss_amount) net_profit_loss,
             '''
            || p_app_user_id
            || ''' app_user_id
       FROM sales_details s
   GROUP BY branch_code
   ORDER BY branch_code ';
      ELSIF w_sales_report_type = 'CN'
      THEN
         -- Product wise profit and loss
         w_sql_stat :=
               w_sql_stat
            || ' )
     SELECT COALESCE ((SELECT branch_center_code||'' - ''||center_name from delar_center c where c.center_code=s.center_code),''Branch Office''),
			sum(total_purchase_value) total_purchase_value,
			sum(product_price) sales_price,
			sum(quantity) quantity,
			sum(returned_quantity) returned_quantity,
			sum(total_price) total_price,
			sum(discount_amount) discount_amount,
            sum (profit_amount) profit_amount,
            sum (loss_amount) loss_amount,
            sum (profit_amount - loss_amount) net_profit_loss,
             '''
            || p_app_user_id
            || ''' app_user_id
       FROM sales_details s
   GROUP BY center_code
   ORDER BY center_code ';
      ELSIF w_sales_report_type = 'IN'
      THEN
         -- Product wise profit and loss
         w_sql_stat := w_sql_stat || ' )
     SELECT invoice_number,
			sum(total_purchase_value) total_purchase_value,
			sum(product_price) sales_price,
			sum(quantity) quantity,
			sum(returned_quantity) returned_quantity,
			sum(total_price) total_price,
			sum(discount_amount) discount_amount,
            sum (profit_amount) profit_amount,
            sum (loss_amount) loss_amount,
            sum (profit_amount - loss_amount) net_profit_loss,
             ''' || p_app_user_id || ''' app_user_id
       FROM sales_details
   GROUP BY invoice_number
   ORDER BY invoice_number ';
      END IF;

      ---RAISE EXCEPTION USING MESSAGE = w_sql_stat;

      EXECUTE w_sql_stat;
   END IF;

   o_status := 'S';
   o_errm := '';
EXCEPTION
   WHEN OTHERS
   THEN
      o_errm := SQLERRM;
      o_status := 'E';
END;
$$;


ALTER FUNCTION public.fn_run_sales_report(p_app_user_id character, p_report_name character, OUT o_status character, OUT o_errm character) OWNER TO postgres;

--
-- Name: fn_sales_change_center_id(character, character); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_sales_change_center_id(p_old_center_id character, p_new_center_id character, OUT o_status character, OUT o_errm character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_errm         VARCHAR;
   w_status       VARCHAR;
   center_info    RECORD;
   client_info    RECORD;
   account_info   RECORD;
BEGIN
   FOR center_info IN (SELECT center_code, delar_id
                         FROM sales_center
                        WHERE center_code = p_old_center_id)
   LOOP
      UPDATE sales_cntreinfo_model
         SET center_code = p_new_center_id,
             delar_id = cast (p_new_center_id AS INTEGER)
       WHERE id = center_info.id;
   END LOOP;

   FOR client_info IN (SELECT id, client_id
                         FROM sales_clients
                        WHERE client_center_code = p_old_center_id)
   LOOP
      UPDATE sales_clients
         SET client_center_code = p_new_center_id,
             delar_id = cast (p_new_center_id AS INTEGER)
       WHERE id = client_info.id;
   END LOOP;

   FOR account_info IN (SELECT id, client_id
                          FROM sales_accounts_balance
                         WHERE center_code = p_old_center_id)
   LOOP
      UPDATE sales_accounts_balance
         SET center_code = p_new_center_id,
             delar_id = cast (p_new_center_id AS INTEGER)
       WHERE id = account_info.id;
   END LOOP;

   BEGIN
      INSERT INTO sales_client_id_changes_hist (old_client_id,
                                                new_client_id,
                                                app_data_time)
           VALUES (p_old_client_id, p_new_client_id, current_timestamp);
   END;

   o_status := 'S';
   o_errm := '';
EXCEPTION
   WHEN OTHERS
   THEN
      IF w_status = 'E'
      THEN
         o_status := w_status;
         o_errm := w_errm;
      ELSE
         o_errm := SQLERRM;
         o_status := 'E';
      END IF;
END;
$$;


ALTER FUNCTION public.fn_sales_change_center_id(p_old_center_id character, p_new_center_id character, OUT o_status character, OUT o_errm character) OWNER TO postgres;

--
-- Name: fn_sales_change_client_id(character, character); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_sales_change_client_id(p_old_client_id character, p_new_client_id character, OUT o_status character, OUT o_errm character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_errm         VARCHAR;
   w_status       VARCHAR;
   client_info    RECORD;
   account_info   RECORD;
BEGIN
   FOR client_info IN (SELECT client_id
                         FROM sales_clients
                        WHERE client_id = p_old_client_id)
   LOOP
      UPDATE sales_clients
         SET client_id = p_new_client_id
       WHERE client_id = client_info.client_id;

      UPDATE sales_clients
         SET client_id = p_new_client_id
       WHERE client_id = client_info.client_id;

      UPDATE sales_sales_master
         SET customer_id = p_new_client_id
       WHERE customer_id = p_old_client_id;

      UPDATE sales_sales_return_details
         SET client_id = p_new_client_id
       WHERE client_id = p_old_client_id;

      UPDATE sales_order_master
         SET customer_id = p_new_client_id
       WHERE customer_id = p_old_client_id;

      UPDATE sales_sales_details
         SET client_id = p_new_client_id
       WHERE client_id = p_old_client_id;

      UPDATE sales_emi_setup
         SET client_id = p_new_client_id
       WHERE client_id = p_old_client_id;

      UPDATE sales_fees_history
         SET client_id = p_new_client_id
       WHERE client_id = p_old_client_id;

      UPDATE micfin_passbook_issue
         SET client_id = p_new_client_id
       WHERE client_id = p_old_client_id;

      UPDATE micfin_nominee_details
         SET client_id = p_new_client_id
       WHERE client_id = p_old_client_id;

      UPDATE micfin_guarantor_details
         SET client_id = p_new_client_id
       WHERE client_id = p_old_client_id;
   END LOOP;

   FOR account_info IN (SELECT account_number, client_id
                          FROM finance_accounts_balance
                         WHERE client_id = p_old_client_id)
   LOOP
      UPDATE finance_accounts_balance
         SET client_id = p_new_client_id
       WHERE client_id = p_old_client_id;

      UPDATE finance_deposit_receive
         SET client_id = p_new_client_id
       WHERE account_number = account_info.account_number;

      UPDATE finance_deposit_payment
         SET client_id = p_new_client_id
       WHERE account_number = account_info.account_number;
   END LOOP;

   BEGIN
      INSERT INTO sales_client_id_changes_hist (old_client_id,
                                                new_client_id,
                                                app_data_time)
           VALUES (p_old_client_id, p_new_client_id, current_timestamp);
   END;

   o_status := 'S';
   o_errm := '';
EXCEPTION
   WHEN OTHERS
   THEN
      IF w_status = 'E'
      THEN
         o_status := w_status;
         o_errm := w_errm;
      ELSE
         o_errm := SQLERRM;
         o_status := 'E';
      END IF;
END;
$$;


ALTER FUNCTION public.fn_sales_change_client_id(p_old_client_id character, p_new_client_id character, OUT o_status character, OUT o_errm character) OWNER TO postgres;

--
-- Name: fn_sales_client_center_transfer(character, character); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_sales_client_center_transfer(p_client_id character, p_new_center_code character, OUT o_status character, OUT o_errm character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_errm              VARCHAR;
   w_status            VARCHAR;
   client_info         RECORD;
   account_info        RECORD;
   w_delar_id          INTEGER;
   w_old_center_code   VARCHAR;
BEGIN
   BEGIN
      SELECT delar_id
        INTO STRICT w_delar_id
        FROM sales_cntreinfo_model
       WHERE center_code = p_new_center_code;
   EXCEPTION
      WHEN NO_DATA_FOUND
      THEN
         w_status := 'E';
         w_errm := 'Invalid Center Code!';
         RAISE EXCEPTION USING MESSAGE = w_errm;
   END;

   FOR client_info IN (SELECT id, client_id, client_center_code
                         FROM sales_clients
                        WHERE client_id = p_client_id)
   LOOP
      w_old_center_code := client_info.client_center_code;

      UPDATE sales_clients
         SET client_center_code = p_new_center_code, delar_id = w_delar_id
       WHERE id = client_info.id;

      UPDATE sales_dps_receive
         SET center_code = p_new_center_code
       WHERE client_id = p_client_id;

      UPDATE sales_deprcv_model
         SET center_code = p_new_center_code
       WHERE client_id = p_client_id;

      UPDATE sales_fees_history
         SET center_code = p_new_center_code
       WHERE client_id = p_client_id;

      UPDATE sales_emircv_model
         SET center_code = p_new_center_code
       WHERE client_id = p_client_id;

      UPDATE sales_emisetup_model
         SET center_code = p_new_center_code
       WHERE client_id = p_client_id;

      UPDATE sales_deprepay_model
         SET center_code = p_new_center_code
       WHERE client_id = p_client_id;

      UPDATE sales_installment_collection
         SET center_code = p_new_center_code, delar_id = w_delar_id
       WHERE client_id = p_client_id;

      UPDATE sales_sales_master
         SET delar_id = w_delar_id
       WHERE customer_id = p_client_id;
   END LOOP;

   FOR account_info IN (SELECT id, client_id
                          FROM sales_accounts_balance
                         WHERE client_id = p_client_id)
   LOOP
      UPDATE sales_accounts_balance
         SET center_code = p_new_center_code, delar_id = w_delar_id
       WHERE id = account_info.id;
   END LOOP;

   BEGIN
      INSERT INTO sales_client_center_trf_hist (client_id,
                                                old_center_code,
                                                new_center_code,
                                                app_data_time)
           VALUES (p_client_id,
                   w_old_center_code,
                   p_new_center_code,
                   current_timestamp);
   END;

   o_status := 'S';
   o_errm := '';
EXCEPTION
   WHEN OTHERS
   THEN
      IF w_status = 'E'
      THEN
         o_status := w_status;
         o_errm := w_errm;
      ELSE
         o_errm := SQLERRM;
         o_status := 'E';
      END IF;
END;
$$;


ALTER FUNCTION public.fn_sales_client_center_transfer(p_client_id character, p_new_center_code character, OUT o_status character, OUT o_errm character) OWNER TO postgres;

--
-- Name: fn_sales_emibal_hist(character, character, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_sales_emibal_hist(p_account_number character, p_emi_reference_no character, p_ason_date date, OUT o_status character, OUT o_errm character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   rec_emi_list       RECORD;
   w_status           VARCHAR;
   w_errm             VARCHAR;
   w_calc_from_date   DATE;
   w_calc_upto_date   DATE;
   w_closer_date      DATE;
BEGIN
   FOR rec_emi_list
      IN (SELECT branch_code,
                 center_code,
                 account_number,
                 emi_reference_no,
                 last_emi_hist_update,
                 last_emi_payment_date,
                 total_emi_due
            FROM sales_emi_setup
           WHERE     account_number = p_account_number
                 AND emi_reference_no = p_emi_reference_no
                 AND emi_cancel_on IS NULL)
   LOOP
      w_calc_from_date := rec_emi_list.last_emi_hist_update;
      w_calc_upto_date := rec_emi_list.last_emi_payment_date;

      DELETE FROM sales_emi_history
            WHERE     account_number = p_account_number
                  AND emi_reference_no = rec_emi_list.emi_reference_no
                  AND inst_receive_date >= w_calc_from_date;

      INSERT INTO sales_emi_history (branch_code,
                                     center_code,
                                     account_number,
                                     emi_reference_no,
                                     emi_rate,
                                     emi_inst_amount,
                                     inst_receive_date,
                                     inst_receive_amount,
                                     total_installment_due,
                                     total_installment_payment,
                                     total_installment_overdue,
                                     total_installment_advance,
                                     total_emi_outstanding,
                                     emi_principal_outstanding,
                                     emi_profit_outstanding,
                                     emi_total_payment,
                                     emi_principal_payment,
                                     emi_profit_payment,
                                     total_advance_recover,
                                     principal_advance_recover,
                                     profit_advance_recover,
                                     total_due_recover,
                                     principal_due_recover,
                                     profit_due_recover,
                                     emi_total_overdue,
                                     emi_principal_overdue,
                                     emi_profit_overdue,
                                     app_user_id,
                                     app_data_time)
         WITH
            emi_receive_details
            AS
               (SELECT branch_code,
                       account_number,
                       emi_reference_no,
                       inst_receive_date inst_receive_date,
                       inst_receive_amount,
                       cum_receive_amount
                  FROM (SELECT branch_code,
                               account_number,
                               emi_reference_no,
                               inst_receive_date,
                               inst_receive_amount,
                               sum (inst_receive_amount)
                               OVER (
                                  PARTITION BY branch_code,
                                               account_number,
                                               emi_reference_no
                                  ORDER BY
                                     branch_code,
                                     account_number,
                                     emi_reference_no,
                                     inst_receive_date) cum_receive_amount
                          FROM (  SELECT branch_code,
                                         account_number,
                                         emi_reference_no,
                                         inst_receive_date,
                                         inst_receive_amount
                                    FROM (SELECT branch_code,
                                                 account_number,
                                                 emi_reference_no
                                                    emi_reference_no,
                                                 inst_receive_date
                                                    inst_receive_date,
                                                 inst_receive_amount
                                                    inst_receive_amount
                                            FROM sales_emi_history h
                                           WHERE     h.account_number =
                                                     rec_emi_list.account_number
                                                 AND h.emi_reference_no =
                                                     rec_emi_list.emi_reference_no
                                                 AND h.inst_receive_date =
                                                     (SELECT max (
                                                                inst_receive_date)
                                                       FROM sales_emi_history b
                                                      WHERE     b.account_number =
                                                                rec_emi_list.account_number
                                                            AND b.emi_reference_no =
                                                                rec_emi_list.emi_reference_no
                                                            AND b.inst_receive_date <
                                                                w_calc_from_date)
                                          UNION ALL
                                            SELECT branch_code,
                                                   account_number,
                                                   emi_reference_no
                                                      emi_reference_no,
                                                   receive_date
                                                      inst_receive_date,
                                                   sum (receive_amount)
                                                      inst_receive_amount
                                              FROM sales_emi_receive
                                             WHERE     account_number =
                                                       rec_emi_list.account_number
                                                   AND emi_reference_no =
                                                       rec_emi_list.emi_reference_no
                                                   AND receive_date >=
                                                       w_calc_from_date
                                                   AND receive_amount > 0
                                          GROUP BY branch_code,
                                                   account_number,
                                                   emi_reference_no,
                                                   receive_date) T
                                ORDER BY account_number,
                                         emi_reference_no,
                                         inst_receive_date) t) t),
            emisetup_details
            AS
               (SELECT branch_code,
                       account_number,
                       emi_reference_no,
                       total_emi_amount,
                       number_of_installment,
                       emi_rate,
                       emi_inst_amount
                          inst_amount,
                       emi_inst_repay_from_date
                          inst_from_date,
                       emi_inst_frequency
                          inst_freq,
                       fn_get_noof_installment_due (emi_inst_frequency,
                                                    emi_inst_repay_from_date,
                                                    p_ason_date)
                          noof_installment_due,
                       (CASE
                           WHEN emi_inst_frequency = 'W' THEN 7
                           WHEN emi_inst_frequency = 'M' THEN 30
                           WHEN emi_inst_frequency = 'Q' THEN 90
                           WHEN emi_inst_frequency = 'H' THEN (365 / 2)
                           WHEN emi_inst_frequency = 'Y' THEN 365
                        END)
                          inst_interval_days
                  FROM sales_emi_setup
                 WHERE     account_number = rec_emi_list.account_number
                       AND emi_reference_no = rec_emi_list.emi_reference_no
                       AND emi_cancel_by IS NULL),
            emi_summary
            AS
               (  SELECT s.branch_code,
                         s.account_number,
                         s.emi_reference_no,
                         s.total_emi_amount,
                         s.number_of_installment,
                         s.inst_amount,
                         s.emi_rate,
                         s.inst_from_date,
                         s.inst_freq,
                         s.inst_interval_days,
                         r.inst_receive_date,
                         r.inst_receive_amount,
                         r.cum_receive_amount,
                         CAST (
                            FLOOR (r.cum_receive_amount / s.inst_amount)
                               AS INTEGER) total_inst_receive,
                         noof_installment_due total_due_inst,
                         (CASE
                             WHEN (r.inst_receive_date - s.inst_from_date) > 0
                             THEN
                                  CAST (
                                     FLOOR (
                                          (  r.inst_receive_date
                                           - s.inst_from_date)
                                        / s.inst_interval_days) AS INTEGER)
                                * s.inst_amount
                             ELSE
                                0
                          END) inst_due_amount
                    FROM emi_receive_details r, emisetup_details s
                   WHERE     r.account_number = s.account_number
                         AND r.emi_reference_no = s.emi_reference_no
                ORDER BY s.branch_code,
                         s.account_number,
                         s.emi_reference_no,
                         r.inst_receive_date),
            emi_duedetails
            AS
               (SELECT branch_code,
                       account_number,
                       emi_reference_no,
                       total_emi_amount,
                       number_of_installment,
                       inst_amount,
                       emi_rate,
                       inst_from_date,
                       inst_freq,
                       inst_interval_days,
                       inst_receive_date,
                       inst_receive_amount,
                       cum_receive_amount,
                       total_inst_receive,
                       (CASE
                           WHEN total_due_inst > number_of_installment
                           THEN
                              number_of_installment
                           ELSE
                              total_due_inst
                        END) total_due_inst,
                       (CASE
                           WHEN total_emi_amount > inst_due_amount
                           THEN
                              inst_due_amount
                           ELSE
                              total_emi_amount
                        END) inst_due_amount
                  FROM emi_summary),
            emi_details
            AS
               (SELECT branch_code,
                       account_number,
                       emi_reference_no,
                       inst_amount,
                       emi_rate,
                       inst_receive_date,
                       inst_receive_amount,
                       total_due_inst,
                       total_inst_receive,
                       (CASE
                           WHEN (total_due_inst - total_inst_receive) > 0
                           THEN
                              (total_due_inst - total_inst_receive)
                           ELSE
                              0
                        END)
                          total_od_inst,
                       (CASE
                           WHEN (total_inst_receive - total_due_inst) > 0
                           THEN
                              (total_inst_receive - total_due_inst)
                           ELSE
                              0
                        END)
                          total_adv_inst,
                       cum_receive_amount
                          emi_total_payment,
                         cum_receive_amount
                       - (cum_receive_amount * (emi_rate / 100))
                          emi_principal_payment,
                       cum_receive_amount * (emi_rate / 100)
                          emi_profit_payment,
                       inst_due_amount
                          total_emi_outstanding,
                       inst_due_amount - (inst_due_amount * (emi_rate / 100))
                          emi_principal_outstanding,
                       inst_due_amount * (emi_rate / 100)
                          emi_profit_outstanding
                  FROM emi_duedetails),
            emi_partition
            AS
               (SELECT branch_code,
                       account_number,
                       emi_reference_no,
                       emi_rate emi_profit_rate,
                       inst_amount emi_inst_amount,
                       inst_receive_date,
                       inst_receive_amount,
                       total_due_inst,
                       total_inst_receive,
                       total_od_inst,
                       total_adv_inst,
                       emi_total_payment,
                       emi_principal_payment,
                       emi_profit_payment,
                       total_emi_outstanding,
                       emi_principal_outstanding,
                       emi_profit_outstanding,
                       (CASE
                           WHEN (total_emi_outstanding - emi_total_payment) >
                                0
                           THEN
                              (total_emi_outstanding - emi_total_payment)
                           ELSE
                              0
                        END) emi_total_overdue,
                       (CASE
                           WHEN (emi_profit_outstanding - emi_profit_payment) >
                                0
                           THEN
                              (emi_profit_outstanding - emi_profit_payment)
                           ELSE
                              0
                        END) emi_profit_overdue,
                       (CASE
                           WHEN (  emi_principal_outstanding
                                 - emi_principal_payment) >
                                0
                           THEN
                              (  emi_principal_outstanding
                               - emi_principal_payment)
                           ELSE
                              0
                        END) emi_principal_overdue,
                       (CASE
                           WHEN (emi_total_payment - total_emi_outstanding) >
                                0
                           THEN
                              (emi_total_payment - total_emi_outstanding)
                           ELSE
                              0
                        END) emi_total_advance,
                       (CASE
                           WHEN (  emi_principal_payment
                                 - emi_principal_outstanding) >
                                0
                           THEN
                              (  emi_principal_payment
                               - emi_principal_outstanding)
                           ELSE
                              0
                        END) emi_principal_advance,
                       (CASE
                           WHEN (emi_profit_payment - emi_profit_outstanding) >
                                0
                           THEN
                              (emi_profit_payment - emi_profit_outstanding)
                           ELSE
                              0
                        END) emi_profit_advance,
                       'SYSTEM' app_user_id,
                       current_timestamp app_data_time
                  FROM emi_details),
            final_emi_amount
            AS
               (SELECT branch_code,
                       account_number,
                       emi_reference_no,
                       emi_profit_rate,
                       emi_inst_amount,
                       inst_receive_date,
                       inst_receive_amount,
                       total_due_inst,
                       total_inst_receive,
                       total_od_inst,
                       total_adv_inst,
                       total_emi_outstanding,
                       emi_principal_outstanding,
                       emi_profit_outstanding,
                       emi_total_payment,
                       emi_principal_payment,
                       emi_profit_payment,
                       emi_total_advance,
                       emi_principal_advance,
                       emi_profit_advance,
                       (CASE
                           WHEN (    inst_receive_amount > emi_inst_amount
                                 AND emi_total_advance <
                                     inst_receive_amount - emi_inst_amount)
                           THEN
                              (  inst_receive_amount
                               - emi_inst_amount
                               - emi_total_advance)
                           ELSE
                              0
                        END) total_due_recover,
                       emi_total_overdue,
                       emi_principal_overdue,
                       emi_profit_overdue,
                       app_user_id,
                       app_data_time
                  FROM emi_partition)
         SELECT branch_code,
                rec_emi_list.center_code,
                account_number,
                emi_reference_no,
                emi_profit_rate,
                emi_inst_amount,
                inst_receive_date,
                inst_receive_amount,
                total_due_inst,
                total_inst_receive,
                total_od_inst,
                total_adv_inst,
                total_emi_outstanding,
                emi_principal_outstanding,
                emi_profit_outstanding,
                emi_total_payment,
                emi_principal_payment,
                emi_profit_payment,
                emi_total_advance,
                emi_principal_advance,
                emi_profit_advance,
                total_due_recover,
                  total_due_recover
                - (total_due_recover * (emi_profit_rate / 100))
                   principal_due_recover,
                total_due_recover * (emi_profit_rate / 100)
                   profit_due_recover,
                emi_total_overdue,
                emi_principal_overdue,
                emi_profit_overdue,
                app_user_id,
                app_data_time
           FROM final_emi_amount;

      DELETE FROM sales_emi_history
            WHERE id =
                  (SELECT id
                    FROM (  SELECT min (id) id,
                                   count (id) total_row,
                                   branch_code,
                                   account_number,
                                   emi_reference_no,
                                   inst_receive_date
                              FROM sales_emi_history
                             WHERE     branch_code = rec_emi_list.branch_code
                                   AND account_number = p_account_number
                                   AND emi_reference_no =
                                       rec_emi_list.emi_reference_no
                          GROUP BY branch_code,
                                   account_number,
                                   emi_reference_no,
                                   inst_receive_date) t
                   WHERE total_row > 1);

      IF rec_emi_list.total_emi_due = 0
      THEN
         w_closer_date := current_date;
      ELSE
         w_closer_date := NULL;
      END IF;

      UPDATE sales_emi_setup
         SET last_emi_hist_update = w_calc_upto_date,
             is_balance_updated = TRUE,
             emi_closer_date = w_closer_date
       WHERE     branch_code = rec_emi_list.branch_code
             AND account_number = p_account_number
             AND emi_reference_no = rec_emi_list.emi_reference_no;
   END LOOP;

   o_status := 'S';
   o_errm := '';
EXCEPTION
   WHEN OTHERS
   THEN
      IF w_status = 'E'
      THEN
         o_status := w_status;
         o_errm := w_errm;
      ELSE
         o_status := 'E';
         o_errm := SQLERRM;
      END IF;
END;
$$;


ALTER FUNCTION public.fn_sales_emibal_hist(p_account_number character, p_emi_reference_no character, p_ason_date date, OUT o_status character, OUT o_errm character) OWNER TO postgres;

--
-- Name: fn_sales_get_center_emi_detail_amount(character, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_sales_get_center_emi_detail_amount(p_center_code character, p_ason_date date, OUT o_total_emi_amount numeric, OUT o_total_emi_due numeric, OUT o_total_emi_recover numeric, OUT o_total_installment_amount numeric, OUT o_asonday_total_recover numeric, OUT o_asonday_due_recover numeric, OUT o_asonday_recover numeric, OUT o_asonday_advance_recover numeric) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   W_MESSAGE                   CHARACTER (20);
   W_RETURN                    NUMERIC (22, 2) := 0;
   w_instrepay_repay_amt       NUMERIC (22, 2) := 0;
   w_installment_due_amount    NUMERIC (22, 2) := 0;
   w_total_emi_due             NUMERIC (22, 2) := 0;
   w_total_emi_amount          NUMERIC (22, 2) := 0;
   w_total_emi_recover         NUMERIC (22, 2) := 0;

   w_asonday_total_recover     NUMERIC (22, 2) := 0;
   w_asonday_due_recover       NUMERIC (22, 2) := 0;
   w_asonday_recover           NUMERIC (22, 2) := 0;
   w_asonday_advance_recover   NUMERIC (22, 2) := 0;
   O_STATUS                    CHARACTER (20);
   O_ERRM                      CHARACTER (100);
   W_STATUS                    CHARACTER (20);
BEGIN
   BEGIN
      SELECT sum (instrepay_repay_amt) instrepay_repay_amt,
             sum (
                (  (total_installment_due - total_installment_paid)
                 * instrepay_repay_amt)) installment_due_amount,
             sum (total_emi_due) total_emi_due,
             sum (total_emi_amount) total_emi_amount,
             sum (instrepay_tot_repay_amt) total_emi_recover
        INTO w_instrepay_repay_amt,
             w_installment_due_amount,
             w_total_emi_due,
             w_total_emi_amount,
             w_total_emi_recover
        FROM (SELECT instrepay_repay_amt,
                     total_emi_due,
                     total_emi_amount,
                     instrepay_tot_repay_amt,
                     CAST (
                        (FLOOR (
                              (p_ason_date - instrepay_repay_from_date)
                            / (CASE
                                  WHEN instrepay_repay_freq = 'W'
                                  THEN
                                     7
                                  WHEN instrepay_repay_freq = 'M'
                                  THEN
                                     30
                                  WHEN instrepay_repay_freq = 'Q'
                                  THEN
                                     90
                                  WHEN instrepay_repay_freq = 'H'
                                  THEN
                                     (365 / 2)
                                  WHEN instrepay_repay_freq = 'Y'
                                  THEN
                                     365
                               END))) AS INTEGER) total_installment_due,
                     CAST (
                        FLOOR (instrepay_tot_repay_amt / instrepay_repay_amt)
                           AS INTEGER) total_installment_paid
                FROM sales_emisetup_model e
               WHERE     e.center_code = p_center_code
                     AND total_emi_due > 0
                     AND e.instrepay_repay_from_date <= p_ason_date) t;

      W_RETURN := COALESCE (w_installment_due_amount, 0.00);
   END;


   WITH
      emi_receive_amount
      AS
         (SELECT emi_inst_amount,
                 emi_profit_rate,
                 inst_receive_amount,
                 (CASE
                     WHEN (    inst_receive_amount > emi_inst_amount
                           AND emi_total_advance <
                               inst_receive_amount - emi_inst_amount)
                     THEN
                        (  inst_receive_amount
                         - emi_inst_amount
                         - emi_total_advance)
                     ELSE
                        0
                  END) emi_due_recover,
                 emi_total_payment,
                 emi_principal_payment,
                 emi_profit_payment,
                 total_emi_outstanding,
                 emi_principal_outstanding,
                 emi_profit_outstanding,
                 emi_total_overdue,
                 emi_principal_overdue,
                 emi_profit_overdue,
                 emi_total_advance,
                 emi_principal_advance,
                 emi_profit_advance
            FROM sales_emi_history
           WHERE     center_code = p_center_code
                 AND inst_receive_date = p_ason_date),
      emi_recovery_summary
      AS
         (SELECT emi_inst_amount,
                 emi_profit_rate,
                 inst_receive_amount,
                 emi_due_recover,
                 emi_total_advance,
                 (inst_receive_amount - (emi_due_recover + emi_inst_amount))
                    ason_day_recover,
                 emi_total_payment,
                 emi_principal_payment,
                 emi_profit_payment,
                 total_emi_outstanding,
                 emi_principal_outstanding,
                 emi_profit_outstanding,
                 emi_total_overdue,
                 emi_principal_overdue,
                 emi_profit_overdue,
                 emi_principal_advance,
                 emi_profit_advance
            FROM emi_receive_amount)
   SELECT sum (inst_receive_amount) total_recover_amount,
          sum (emi_due_recover) total_due_recover,
          sum (ason_day_recover) total_ason_day_recover,
          sum (emi_total_advance) emi_total_advance
     INTO w_asonday_total_recover,
          w_asonday_due_recover,
          w_asonday_recover,
          w_asonday_advance_recover
     FROM emi_recovery_summary;

   o_total_emi_amount := COALESCE (w_total_emi_amount, 0.00);
   o_total_emi_due := COALESCE (w_total_emi_due, 0.00);
   o_total_installment_amount := COALESCE (w_instrepay_repay_amt, 0.00);
   o_total_emi_recover := COALESCE (w_total_emi_recover, 0.00);
   o_asonday_total_recover := COALESCE (w_asonday_total_recover, 0.00);
   o_asonday_due_recover := COALESCE (w_asonday_due_recover, 0.00);
   o_asonday_recover := COALESCE (w_asonday_recover, 0.00);
   o_asonday_advance_recover := COALESCE (w_asonday_advance_recover, 0.00);
END;
$$;


ALTER FUNCTION public.fn_sales_get_center_emi_detail_amount(p_center_code character, p_ason_date date, OUT o_total_emi_amount numeric, OUT o_total_emi_due numeric, OUT o_total_emi_recover numeric, OUT o_total_installment_amount numeric, OUT o_asonday_total_recover numeric, OUT o_asonday_due_recover numeric, OUT o_asonday_recover numeric, OUT o_asonday_advance_recover numeric) OWNER TO postgres;

--
-- Name: fn_sales_online_order_accept(integer, character, character, character, date, character, numeric, numeric, character, character, character, character); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_sales_online_order_accept(p_branch_code integer, p_app_user_id character, p_order_number character, p_invoice_number character, p_invoice_date date, p_employee_id character, p_pay_amount numeric, p_invoice_discount numeric, p_tran_type_code character, p_bill_receive_gl character, p_bill_due_gl character, p_payment_document character, OUT o_status character, OUT o_errm character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_status         VARCHAR;
   w_errm           VARCHAR;
   rec_order_list   RECORD;
   w_batch_number   INTEGER;
BEGIN
   BEGIN
      FOR rec_order_list IN (SELECT *
                               FROM ecom_order_master
                              WHERE order_number = p_order_number)
      LOOP
         IF rec_order_list.status = 'A'
         THEN
            RAISE EXCEPTION USING MESSAGE = 'This Order Already Accepted!';
         END IF;

         --RAISE EXCEPTION USING MESSAGE = p_order_number;

         INSERT INTO sales_sales_details_temp (invoice_number,
                                               product_id,
                                               product_bar_code,
                                               product_name,
                                               product_model,
                                               sales_account_number,
                                               serial_no,
                                               service_type,
                                               service_start_date,
                                               service_end_date,
                                               service_card_no,
                                               product_price,
                                               quantity,
                                               total_price,
                                               profit_amount,
                                               discount_rate,
                                               discount_amount,
                                               status,
                                               comments,
                                               app_user_id,
                                               app_data_time,
                                               details_branch_code)
            SELECT NULL,
                   product_id,
                   NULL,
                   'NA',
                   NULL,
                   NULL,
                   serial_no,
                   NULL,
                   NULL,
                   NULL,
                   NULL,
                   product_price,
                   order_quantity,
                   total_price,
                   profit_amount,
                   discount_rate,
                   discount_amount,
                   status,
                   comments,
                   app_user_id,
                   app_data_time,
                   p_branch_code branch_code
              FROM ecom_order_details
             WHERE order_number = p_order_number;

         SELECT *
         INTO w_status, w_errm, w_batch_number
         FROM fn_sales_sales_post (
                 p_branch_code,
                 p_app_user_id,
                 p_invoice_number,
                 rec_order_list.customer_phone,
                 CAST (rec_order_list.customer_id AS VARCHAR),
                 rec_order_list.customer_name,
                 rec_order_list.customer_address,
                 rec_order_list.account_number,
                 p_employee_id,
                 p_pay_amount,
                 p_invoice_discount,
                 p_tran_type_code,
                 p_bill_receive_gl,
                 p_bill_due_gl,
                 p_payment_document,
                 0.00,
                 rec_order_list.discount_amount,
                 p_invoice_date,
                 rec_order_list.latitude,
                 rec_order_list.longitude);

         IF w_status = 'E'
         THEN
            RAISE EXCEPTION USING MESSAGE = w_errm;
         ELSE
            UPDATE ecom_order_master
               SET status = 'A'
             WHERE     order_number = p_order_number
                   AND branch_code = p_branch_code;

            UPDATE sales_sales_master
               SET order_number = p_order_number
             WHERE     invoice_number = p_invoice_number
                   AND invoice_date = p_invoice_date;
         END IF;
      END LOOP;
   END;

   o_status := 'S';
   o_errm := '';
EXCEPTION
   WHEN OTHERS
   THEN
      IF w_status = 'E'
      THEN
         o_status := w_status;
         o_errm := w_errm;
      ELSE
         o_status := 'E';
         o_errm := SQLERRM;
      END IF;
END;
$$;


ALTER FUNCTION public.fn_sales_online_order_accept(p_branch_code integer, p_app_user_id character, p_order_number character, p_invoice_number character, p_invoice_date date, p_employee_id character, p_pay_amount numeric, p_invoice_discount numeric, p_tran_type_code character, p_bill_receive_gl character, p_bill_due_gl character, p_payment_document character, OUT o_status character, OUT o_errm character) OWNER TO postgres;

--
-- Name: fn_sales_order_accept(integer, character, character, character, date, character, numeric, numeric, character, character, character, character); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_sales_order_accept(p_branch_code integer, p_app_user_id character, p_order_number character, p_invoice_number character, p_invoice_date date, p_employee_id character, p_pay_amount numeric, p_invoice_discount numeric, p_tran_type_code character, p_bill_receive_gl character, p_bill_due_gl character, p_payment_document character, OUT o_status character, OUT o_errm character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_status             VARCHAR;
   w_errm               VARCHAR;
   rec_order_list       RECORD;
   w_batch_number       INTEGER;
   w_pending_quantity   INTEGER;
   w_center_code        VARCHAR := '0';
   w_total_quantity     INTEGER;
BEGIN
   BEGIN
      FOR rec_order_list IN (SELECT *
                               FROM sales_order_master
                              WHERE order_number = p_order_number)
      LOOP
         IF rec_order_list.status = 'I'
         THEN
            RAISE EXCEPTION USING MESSAGE = 'This Order Already Delivered!';
         END IF;

         BEGIN
            SELECT sum (quantity)
              INTO w_total_quantity
              FROM sales_order_details
             WHERE order_number = p_order_number AND quantity > 0;
         END;

         IF w_total_quantity = 0 OR w_total_quantity IS NULL
         THEN
            RAISE EXCEPTION USING MESSAGE = 'Nothing to delivery!';
         END IF;


         INSERT INTO sales_sales_details_temp (invoice_number,
                                               product_id,
                                               product_bar_code,
                                               product_name,
                                               product_model,
                                               sales_account_number,
                                               serial_no,
                                               service_type,
                                               service_start_date,
                                               service_end_date,
                                               service_card_no,
                                               product_price,
                                               quantity,
                                               total_price,
                                               profit_amount,
                                               discount_rate,
                                               discount_amount,
                                               status,
                                               comments,
                                               app_user_id,
                                               app_data_time,
                                               details_branch_code)
            SELECT p_invoice_number,
                   product_id,
                   NULL,
                   'NA',
                   NULL,
                   NULL,
                   serial_no,
                   service_type,
                   service_start_date,
                   service_end_date,
                   service_card_no,
                   product_price,
                   quantity,
                   total_price,
                   profit_amount,
                   discount_rate,
                   discount_amount,
                   status,
                   comments,
                   app_user_id,
                   app_data_time,
                   branch_code
              FROM sales_order_details
             WHERE order_number = p_order_number AND quantity > 0;

         UPDATE sales_order_details
            SET delivered_quantity = delivered_quantity + quantity,
                quantity = ordered_quantity - (delivered_quantity + quantity),
                delivered_total_price = delivered_total_price + total_price,
                total_price =
                     ordered_total_price
                   - (delivered_total_price + total_price),
                delivered_discount_amount =
                   delivered_discount_amount + discount_amount,
                discount_amount =
                     ordered_discount_amount
                   - (delivered_discount_amount + discount_amount)
          WHERE order_number = p_order_number AND branch_code = p_branch_code;

         SELECT quantity
           INTO w_pending_quantity
           FROM sales_order_details
          WHERE order_number = p_order_number AND branch_code = p_branch_code;

         SELECT center_code
           INTO w_center_code
           FROM sales_clients
          WHERE client_id = rec_order_list.customer_id;


         SELECT *
           INTO w_status, w_errm, w_batch_number
           FROM fn_sales_sales_post (p_branch_code,
                                     w_center_code,
                                     p_app_user_id,
                                     p_invoice_number,
                                     rec_order_list.customer_phone,
                                     rec_order_list.customer_id,
                                     rec_order_list.customer_name,
                                     rec_order_list.customer_address,
                                     rec_order_list.account_number,
                                     p_employee_id,
                                     p_pay_amount,
                                     p_invoice_discount,
                                     p_tran_type_code,
                                     p_bill_receive_gl,
                                     p_bill_due_gl,
                                     p_payment_document,
                                     rec_order_list.total_discount_rate,
                                     rec_order_list.total_discount_amount,
                                     p_invoice_date,
                                     rec_order_list.latitude,
                                     rec_order_list.longitude);

         IF w_status = 'E'
         THEN
            RAISE EXCEPTION USING MESSAGE = w_errm;
         ELSE
            UPDATE sales_order_master
               SET tran_batch_number = w_batch_number
             WHERE     order_number = p_order_number
                   AND branch_code = p_branch_code;

            UPDATE sales_sales_master
               SET order_number = p_order_number
             WHERE     invoice_number = p_invoice_number
                   AND invoice_date = p_invoice_date;

            IF w_pending_quantity = 0
            THEN
               UPDATE sales_order_master
                  SET status = 'I'
                WHERE     order_number = p_order_number
                      AND branch_code = p_branch_code;
            END IF;
         END IF;
      END LOOP;
   END;

   o_status := 'S';
   o_errm := '';
EXCEPTION
   WHEN OTHERS
   THEN
      IF w_status = 'E'
      THEN
         o_status := w_status;
         o_errm := w_errm;
      ELSE
         o_status := 'E';
         o_errm := SQLERRM;
      END IF;
END;
$$;


ALTER FUNCTION public.fn_sales_order_accept(p_branch_code integer, p_app_user_id character, p_order_number character, p_invoice_number character, p_invoice_date date, p_employee_id character, p_pay_amount numeric, p_invoice_discount numeric, p_tran_type_code character, p_bill_receive_gl character, p_bill_due_gl character, p_payment_document character, OUT o_status character, OUT o_errm character) OWNER TO postgres;

--
-- Name: fn_sales_order_post(integer, character, character, character, character, character, character, character, character, character, numeric, character, numeric, numeric, date, numeric, numeric); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_sales_order_post(p_branch_code integer, p_center_code character, p_app_user_id character, p_order_number character, p_customer_phone character, p_customer_id character, p_customer_name character, p_customer_address character, p_account_number character, p_employee_id character, p_pay_amount numeric, p_tran_type_code character, p_discount_rate numeric, p_discount_amount numeric, p_order_date date, p_latitude numeric, p_longitude numeric, OUT o_status character, OUT o_errm character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_error_message              VARCHAR;
   w_batch_number               INTEGER;
   w_check                      BOOLEAN;
   w_account_number             VARCHAR := '0';
   w_transaction_date           DATE;
   product_list                 RECORD;
   w_tran_gl_code               VARCHAR := '0';
   w_cash_transaction           BOOLEAN;
   w_total_leg                  INTEGER;
   w_total_debit_amount         NUMERIC (22, 2) := 0;
   w_total_credit_amount        NUMERIC (22, 2) := 0;
   w_account_banalce            NUMERIC (22, 2) := 0;
   w_credit_limit               NUMERIC (22, 2) := 0;
   w_serial_no                  INTEGER := 0;
   w_product_total_stock        INTEGER := 0;
   w_product_total_sales        INTEGER := 0;
   w_product_available_stock    INTEGER := 0;
   w_product_last_stock_date    DATE;
   w_product_last_sale_date     DATE;
   w_product_last_return_date   DATE;
   w_product_total_returned     INTEGER := 0;
   w_total_purchase_amount      NUMERIC (22, 2) := 0.00;
   w_total_return_amount        NUMERIC (22, 2) := 0.00;
   w_total_sales_amount         NUMERIC (22, 2) := 0.00;
   w_product_total_damage       INTEGER := 0;
   w_total_return_damage        NUMERIC (22, 2) := 0.00;
   w_total_order_quantity       INTEGER := 0;
   w_total_bill_amount          NUMERIC (22, 2) := 0.00;
   w_bill_amount                NUMERIC (22, 2) := 0.00;
   w_due_amount                 NUMERIC (22, 2) := 0.00;
   w_advance_pay                NUMERIC (22, 2) := 0.00;
   w_status                     VARCHAR;
   w_errm                       VARCHAR;
   w_product_name               VARCHAR;
   w_batch_serial               INTEGER := 1;
   w_contra_gl_code             VARCHAR;
   w_tran_debit_credit          VARCHAR := 'C';
   w_employee_id                VARCHAR;
BEGIN
   BEGIN
      SELECT cash_gl_code
        INTO w_tran_gl_code
        FROM appauth_user_settings
       WHERE app_user_id = p_app_user_id;
   END;

   FOR product_list IN (  SELECT invoice_number,
                                 product_id,
                                 serial_no,
                                 service_type,
                                 service_start_date,
                                 service_end_date,
                                 service_card_no,
                                 product_price,
                                 quantity,
                                 total_price,
                                 profit_amount,
                                 discount_rate,
                                 discount_amount,
                                 status,
                                 comments,
                                 app_user_id,
                                 app_data_time
                            FROM sales_sales_details_temp s
                           WHERE s.app_user_id = p_app_user_id
                        ORDER BY serial_no)
   LOOP
      BEGIN
         w_total_order_quantity :=
            w_total_order_quantity + product_list.quantity;
         w_serial_no := w_serial_no + 1;
         w_total_bill_amount :=
            w_total_bill_amount + product_list.total_price;
         w_bill_amount :=
              w_bill_amount
            + product_list.total_price
            - product_list.discount_amount;

         INSERT INTO sales_order_details (order_number,
                                          center_code,
                                          order_date,
                                          product_id,
                                          serial_no,
                                          service_type,
                                          service_start_date,
                                          service_end_date,
                                          service_card_no,
                                          product_price,
                                          ordered_product_price,
                                          quantity,
                                          ordered_quantity,
                                          delivered_quantity,
                                          total_price,
                                          ordered_total_price,
                                          delivered_total_price,
                                          profit_amount,
                                          discount_rate,
                                          ordered_discount_rate,
                                          delivered_discount_rate,
                                          discount_amount,
                                          ordered_discount_amount,
                                          delivered_discount_amount,
                                          status,
                                          comments,
                                          branch_code,
                                          app_user_id,
                                          app_data_time)
              VALUES (p_order_number,
                      p_center_code,
                      p_order_date,
                      product_list.product_id,
                      w_serial_no,
                      product_list.service_type,
                      product_list.service_start_date,
                      product_list.service_end_date,
                      product_list.service_card_no,
                      product_list.product_price,
                      product_list.product_price,
                      product_list.quantity,
                      product_list.quantity,
                      0,
                      product_list.total_price,
                      product_list.total_price,
                      0.00,
                      product_list.profit_amount,
                      product_list.discount_rate,
                      product_list.discount_rate,
                      0.00,
                      product_list.discount_amount,
                      product_list.discount_amount,
                      0.00,
                      'P',
                      product_list.comments,
                      p_branch_code,
                      product_list.app_user_id,
                      current_timestamp);
      END;

      BEGIN
         SELECT product_name
           INTO w_product_name
           FROM sales_products
          WHERE product_id = product_list.product_id;

         SELECT product_available_stock
          INTO w_product_available_stock
          FROM sales_products_inventory_status
         WHERE     product_id = product_list.product_id
               AND branch_code = p_branch_code;
      END;

      /*
            IF w_product_available_stock - product_list.quantity < 0
            THEN
               w_status := 'E';
               w_errm := 'Product ' || w_product_name || ' Out of Stock!';
               RAISE EXCEPTION USING MESSAGE = w_errm;
            END IF;
      */

      UPDATE sales_products_inventory_status
         SET total_order_quantity =
                total_order_quantity + product_list.quantity,
             last_order_date = p_order_date
       WHERE     product_id = product_list.product_id
             AND branch_code = p_branch_code;

      UPDATE sales_products_inventory_status
         SET total_order_quantity =
                total_order_quantity + product_list.quantity,
             last_order_date = p_order_date
       WHERE product_id = product_list.product_id;
   END LOOP;

   w_due_amount := w_bill_amount - p_pay_amount;

   IF w_due_amount < 0
   THEN
      w_advance_pay := p_pay_amount - w_bill_amount;
      w_due_amount := 0;
   END IF;

   INSERT INTO sales_order_master (order_number,
                                   employee_id,
                                   order_date,
                                   customer_id,
                                   account_number,
                                   customer_name,
                                   customer_phone,
                                   customer_address,
                                   tran_type_code,
                                   total_quantity,
                                   total_bill_amount,
                                   bill_amount,
                                   pay_amount,
                                   due_amount,
                                   advance_pay,
                                   total_discount_rate,
                                   total_discount_amount,
                                   status,
                                   order_comments,
                                   branch_code,
                                   center_code,
                                   app_user_id,
                                   app_data_time,
                                   latitude,
                                   longitude)
        VALUES (p_order_number,
                p_employee_id,
                p_order_date,
                P_customer_id,
                p_account_number,
                P_customer_name,
                P_customer_phone,
                p_customer_address,
                p_tran_type_code,
                w_total_order_quantity,
                w_total_bill_amount,
                w_bill_amount,
                p_pay_amount,
                w_due_amount,
                w_advance_pay,
                p_discount_rate,
                p_discount_amount,
                'P',
                NULL,
                p_branch_code,
                p_center_code,
                p_app_user_id,
                current_timestamp,
                p_latitude,
                p_longitude);

   BEGIN
      IF p_pay_amount > 0
      THEN
         INSERT INTO finance_transaction_table (branch_code,
                                                center_code,
                                                transaction_date,
                                                batch_serial,
                                                account_number,
                                                tran_gl_code,
                                                contra_gl_code,
                                                tran_debit_credit,
                                                tran_type,
                                                tran_amount,
                                                available_balance,
                                                tran_person_phone,
                                                tran_person_name,
                                                tran_document_prefix,
                                                tran_document_number,
                                                tran_sign_verified,
                                                system_posted_tran,
                                                transaction_narration,
                                                app_user_id,
                                                app_data_time)
              VALUES (p_branch_code,
                      p_center_code,
                      p_order_date,
                      w_batch_serial,
                      p_account_number,
                      '0',
                      w_tran_gl_code,
                      w_tran_debit_credit,
                      'ORDER',
                      p_pay_amount,
                      0.00,
                      NULL,
                      NULL,
                      NULL,
                      NULL,
                      FALSE,
                      FALSE,
                      'Sales Order Payment',
                      p_app_user_id,
                      current_timestamp);
      END IF;
   END;

   BEGIN
      SELECT *
        INTO w_status, w_errm, w_batch_number
        FROM fn_finance_post_cash_tran (p_branch_code,
                                        p_center_code,
                                        p_app_user_id,
                                        'ORDER',
                                        w_tran_gl_code,
                                        p_order_date,
                                        'Sales Order Posting',
                                        'CR',
                                        'ORDER');

      IF w_status = 'E' AND w_batch_number > 0
      THEN
         RAISE EXCEPTION USING MESSAGE = w_errm;
      ELSE
         UPDATE sales_order_master
            SET tran_batch_number = w_batch_number
          WHERE order_number = p_order_number AND order_date = p_order_date;
      END IF;
   END;

   DELETE FROM sales_sales_details_temp s
         WHERE s.app_user_id = p_app_user_id;


   o_status := 'S';
   o_errm := '';
EXCEPTION
   WHEN OTHERS
   THEN
      IF w_status = 'E'
      THEN
         o_status := w_status;
         o_errm := w_errm;
      ELSE
         o_status := 'E';
         o_errm := SQLERRM;
      END IF;
END;
$$;


ALTER FUNCTION public.fn_sales_order_post(p_branch_code integer, p_center_code character, p_app_user_id character, p_order_number character, p_customer_phone character, p_customer_id character, p_customer_name character, p_customer_address character, p_account_number character, p_employee_id character, p_pay_amount numeric, p_tran_type_code character, p_discount_rate numeric, p_discount_amount numeric, p_order_date date, p_latitude numeric, p_longitude numeric, OUT o_status character, OUT o_errm character) OWNER TO postgres;

--
-- Name: fn_sales_product_inventory_hist(integer, character); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_sales_product_inventory_hist(p_branch_code integer, p_product_code character, OUT o_status character, OUT o_errm character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   rec_date_list                 RECORD;
   rec_date_range                RECORD;
   rec_product_list              RECORD;
   w_calculate_date              DATE;
   w_last_transaction_date       DATE;
   w_first_transaction_date      DATE;
   w_product_available_stock     INTEGER;
   w_cost_of_good_sold_balance   NUMERIC (18, 2);
   w_total_purchase_balance      NUMERIC (18, 2);
   w_total_sales_balance         NUMERIC (18, 2);
   w_product_purchase_rate       NUMERIC (18, 2);
   w_previous_purchase_rate      NUMERIC (18, 2);
   w_previous_available_stock    INTEGER;
   w_status                      VARCHAR;
   w_errm                        VARCHAR;
BEGIN
   FOR rec_product_list
      IN (SELECT COALESCE (
                    inv_balance_upto_date,
                    (least (last_stock_date,
                            last_order_date,
                            last_sale_date,
                            last_stock_return_date,
                            last_sales_return_date))) balance_upto_date,
                 GREATEST (last_stock_date,
                           last_order_date,
                           last_sale_date,
                           last_stock_return_date,
                           last_sales_return_date) last_transaction_date,
                 LEAST (last_stock_date,
                        last_order_date,
                        last_sale_date,
                        last_stock_return_date,
                        last_sales_return_date) first_transaction_date
            FROM sales_products_inventory_status
           WHERE     branch_code = p_branch_code
                 AND product_id = p_product_code
                 AND is_balance_updated = FALSE)
   LOOP
      w_calculate_date := rec_product_list.balance_upto_date;
      w_last_transaction_date := rec_product_list.last_transaction_date;
      w_first_transaction_date := rec_product_list.first_transaction_date;

      ---w_calculate_date := COALESCE (w_calculate_date, w_first_transaction_date - 1);

      --RAISE EXCEPTION USING MESSAGE = w_calculate_date;

      SELECT sum (product_available_stock)
                product_available_stock,
             round (sum (cost_of_good_sold_balance), 2)
                cost_of_good_sold_balance,
             sum (total_purchase_balance)
                total_purchase_balance,
             sum (total_sales_balance)
                total_sales_balance
        INTO w_product_available_stock,
             w_cost_of_good_sold_balance,
             w_total_purchase_balance,
             w_total_sales_balance
        FROM sales_products_inventory_hist
       WHERE     branch_code = p_branch_code
             AND product_id = p_product_code
             AND inv_balance_date =
                 (SELECT max (inv_balance_date)
                   FROM sales_products_inventory_hist
                  WHERE     branch_code = p_branch_code
                        AND product_id = p_product_code
                        AND inv_balance_date < w_calculate_date);

      w_product_available_stock := COALESCE (w_product_available_stock, 0);
      w_cost_of_good_sold_balance :=
         COALESCE (w_cost_of_good_sold_balance, 0.00);
      w_total_purchase_balance := COALESCE (w_total_purchase_balance, 0.00);
      w_total_sales_balance := COALESCE (w_total_sales_balance, 0.00);

      FOR rec_date_range
         IN (WITH
                product
                AS
                   (SELECT product_id
                      FROM sales_products
                     WHERE product_id = p_product_code),
                stock
                AS
                   (SELECT p.product_id, s.stock_date transaction_date
                      FROM sales_stockdetails s, product p
                     WHERE     s.stock_date > w_calculate_date - 1
                           AND s.branch_code = p_branch_code
                           AND s.status = 'S'
                           AND p.product_id = s.product_id),
                stock_return
                AS
                   (SELECT p.product_id, pr.return_date transaction_date
                      FROM sales_stock_return_details pr, product p
                     WHERE     pr.return_date > w_calculate_date - 1
                           AND pr.branch_code = p_branch_code
                           AND pr.product_id = p.product_id
                           AND pr.cancel_by IS NULL),
                sales
                AS
                   (SELECT p.product_id, m.invoice_date transaction_date
                      FROM sales_sales_details s,
                           sales_sales_master m,
                           product p
                     WHERE     s.invoice_number = m.invoice_number
                           AND m.invoice_date > w_calculate_date - 1
                           AND m.branch_code = p_branch_code
                           AND m.status <> 'C'
                           AND s.product_id = p.product_id),
                sales_return
                AS
                   (SELECT p.product_id, sr.return_date transaction_date
                      FROM sales_sales_return_details sr, product p
                     WHERE     sr.return_date > w_calculate_date - 1
                           AND sr.branch_code = p_branch_code
                           AND sr.product_id = p.product_id
                           AND sr.cancel_by IS NULL),
                damage
                AS
                   (SELECT d.product_id, d.damage_date transaction_date
                      FROM sales_product_damage_details d, product p
                     WHERE     d.damage_date > w_calculate_date - 1
                           AND d.branch_code = p_branch_code
                           AND d.product_id = p.product_id
                           AND d.cancel_by IS NULL)
               SELECT DISTINCT transaction_date as_of_date
                 FROM (SELECT transaction_date FROM stock
                       UNION ALL
                       SELECT transaction_date FROM stock_return
                       UNION ALL
                       SELECT transaction_date FROM sales
                       UNION ALL
                       SELECT transaction_date FROM sales_return
                       UNION ALL
                       SELECT transaction_date FROM damage) t
             ORDER BY transaction_date)
      LOOP
         FOR rec_date_list
            IN (WITH
                   product
                   AS
                      (SELECT product_id
                         FROM sales_products
                        WHERE product_id = p_product_code),
                   stock
                   AS
                      (  SELECT s.stock_date transaction_date,
                                p.product_id,
                                sum (s.quantity) quantity,
                                sum (s.purces_price) purces_rate,
                                sum (s.total_price) total_price
                           FROM sales_stockdetails s, product p
                          WHERE     s.stock_date = rec_date_range.as_of_date
                                AND s.branch_code = p_branch_code
                                AND s.status = 'S'
                                AND p.product_id = s.product_id
                       GROUP BY p.product_id, s.stock_date),
                   stock_return
                   AS
                      (  SELECT pr.return_date transaction_date,
                                pr.product_id,
                                sum (pr.returned_quantity) returned_quantity,
                                sum (pr.return_amount) return_amount
                           FROM sales_stock_return_details pr, product p
                          WHERE     pr.return_date = rec_date_range.as_of_date
                                AND pr.branch_code = p_branch_code
                                AND pr.product_id = p.product_id
                                AND pr.cancel_by IS NULL
                       GROUP BY pr.product_id, pr.return_date),
                   sales
                   AS
                      (  SELECT m.invoice_date transaction_date,
                                s.product_id,
                                sum (s.quantity) quantity,
                                sum (s.product_price) unit_price,
                                sum (s.total_price) total_price,
                                sum (s.discount_amount) discount_amount,
                                round (
                                   sum ((s.total_price - s.discount_amount)),
                                   2) net_price,
                                sum ((purchase_rate * s.quantity)) cost_of_good_sold
                           FROM sales_sales_details s,
                                sales_sales_master m,
                                product p
                          WHERE     s.invoice_number = m.invoice_number
                                AND m.invoice_date = rec_date_range.as_of_date
                                AND m.branch_code = p_branch_code
                                AND m.status <> 'C'
                                AND s.product_id = p.product_id
                       GROUP BY s.product_id, m.invoice_date),
                   sales_return
                   AS
                      (  SELECT sr.return_date transaction_date,
                                sr.product_id,
                                sum (sr.returned_quantity) returned_quantity,
                                sum (sr.return_amount) net_price
                           FROM sales_sales_return_details sr, product p
                          WHERE     sr.return_date = rec_date_range.as_of_date
                                AND sr.branch_code = p_branch_code
                                AND sr.product_id = p.product_id
                                AND sr.cancel_by IS NULL
                       GROUP BY sr.product_id, sr.return_date),
                   damage
                   AS
                      (  SELECT d.product_id,
                                d.damage_date transaction_date,
                                sum (d.damage_quantity) damage_quantity,
                                sum (d.damage_amount) damage_amount,
                                sum (d.receive_amount) receive_amount
                           FROM sales_product_damage_details d, product p
                          WHERE     d.damage_date = rec_date_range.as_of_date
                                AND d.branch_code = p_branch_code
                                AND d.product_id = p.product_id
                                AND d.cancel_by IS NULL
                       GROUP BY d.product_id, d.damage_date)
                  SELECT product_id,
                         transaction_date,
                         stock_quantity,
                         stock_total_price,
                         stock_return_quantity,
                         stock_return_total_price,
                         sales_quantity,
                         sales_total_price,
                         sales_discount_amount,
                         sales_return_quantity,
                         sales_return_total_price,
                         cost_of_good_sold,
                         damage_quantity,
                         damage_amount,
                         receive_amount
                    FROM (SELECT product.product_id,
                                 COALESCE (stock.transaction_date,
                                           stock_return.transaction_date,
                                           sales.transaction_date,
                                           sales_return.transaction_date,
                                           damage.transaction_date)
                                    transaction_date,
                                 COALESCE (stock.quantity, 0)
                                    stock_quantity,
                                 COALESCE (stock.total_price, 0)
                                    stock_total_price,
                                 COALESCE (stock_return.returned_quantity, 0)
                                    stock_return_quantity,
                                 COALESCE (stock_return.return_amount, 0)
                                    stock_return_total_price,
                                 COALESCE (sales.quantity, 0)
                                    sales_quantity,
                                 COALESCE (sales.net_price, 0)
                                    sales_total_price,
                                 COALESCE (sales.discount_amount, 0)
                                    sales_discount_amount,
                                 COALESCE (sales_return.returned_quantity, 0)
                                    sales_return_quantity,
                                 COALESCE (sales_return.net_price, 0)
                                    sales_return_total_price,
                                 COALESCE (sales.cost_of_good_sold, 0)
                                    cost_of_good_sold,
                                 COALESCE (damage.damage_quantity, 0)
                                    damage_quantity,
                                 COALESCE (damage.damage_amount, 0)
                                    damage_amount,
                                 COALESCE (damage.receive_amount, 0)
                                    receive_amount
                            FROM product
                                 FULL OUTER JOIN stock
                                    ON (stock.product_id = product.product_id)
                                 FULL OUTER JOIN stock_return
                                    ON (stock_return.product_id =
                                        product.product_id)
                                 FULL OUTER JOIN sales
                                    ON (sales.product_id = product.product_id)
                                 FULL OUTER JOIN sales_return
                                    ON (sales_return.product_id =
                                        product.product_id)
                                 FULL OUTER JOIN damage
                                    ON (damage.product_id = product.product_id))
                         t
                   WHERE transaction_date IS NOT NULL
                ORDER BY transaction_date)
         LOOP
            w_calculate_date := rec_date_list.transaction_date;
            w_product_available_stock :=
                 w_product_available_stock
               + rec_date_list.stock_quantity
               - rec_date_list.stock_return_quantity
               - rec_date_list.sales_quantity
               + rec_date_list.sales_return_quantity
               - rec_date_list.damage_quantity;

            w_cost_of_good_sold_balance :=
               w_cost_of_good_sold_balance + rec_date_list.cost_of_good_sold;

            w_total_purchase_balance :=
                 w_total_purchase_balance
               + rec_date_list.stock_total_price
               - rec_date_list.stock_return_total_price;

            w_total_sales_balance :=
                 w_total_sales_balance
               + rec_date_list.sales_total_price
               - rec_date_list.sales_return_total_price;

            ---- Calculation Purchase Rate

            w_product_purchase_rate := COALESCE (w_product_purchase_rate, 0);

            BEGIN
               SELECT product_available_stock, product_purchase_rate
                 INTO w_previous_available_stock, w_previous_purchase_rate
                 FROM sales_products_inventory_hist
                WHERE     branch_code = p_branch_code
                      AND product_id = p_product_code
                      AND inv_balance_date =
                          (SELECT max (inv_balance_date)
                            FROM sales_products_inventory_hist
                           WHERE     branch_code = p_branch_code
                                 AND product_id = p_product_code
                                 AND inv_balance_date < w_calculate_date);
            END;

            w_previous_available_stock :=
               COALESCE (w_previous_available_stock, 0);
            w_previous_purchase_rate :=
               COALESCE (w_previous_purchase_rate, 0);

            IF    rec_date_list.stock_quantity > 0
               OR w_previous_available_stock > 0
            THEN
               BEGIN
                  w_product_purchase_rate :=
                     (  (  (  w_previous_available_stock
                            * w_previous_purchase_rate)
                         + (rec_date_list.stock_total_price))
                      / (  w_previous_available_stock
                         + rec_date_list.stock_quantity));
               EXCEPTION
                  WHEN OTHERS
                  THEN
                     w_product_purchase_rate := w_previous_purchase_rate;
               END;
            ELSE
               w_product_purchase_rate := w_previous_purchase_rate;
            END IF;

            ---- End of Calculation Purchase Rate

            DELETE FROM sales_products_inventory_hist
                  WHERE     branch_code = p_branch_code
                        AND product_id = p_product_code
                        AND inv_balance_date = w_calculate_date;

            ---RAISE EXCEPTION USING MESSAGE = w_product_available_stock;

            INSERT INTO sales_products_inventory_hist (
                           branch_code,
                           product_id,
                           inv_balance_date,
                           product_total_stock,
                           total_order_quantity,
                           product_total_sales,
                           total_stock_return,
                           total_sales_return,
                           product_total_damage,
                           product_available_stock,
                           product_purchase_rate,
                           total_purchase_amount,
                           total_purchase_balance,
                           total_sales_amount,
                           total_sales_balance,
                           sales_return_amount,
                           total_damage_amount,
                           stock_return_amount,
                           cost_of_good_sold,
                           cost_of_good_sold_balance,
                           total_discount_receive,
                           total_discount_pay,
                           app_user_id,
                           app_data_time)
                 VALUES (p_branch_code,
                         p_product_code,
                         w_calculate_date,
                         rec_date_list.stock_quantity,
                         rec_date_list.damage_quantity,
                         rec_date_list.sales_quantity,
                         rec_date_list.stock_return_quantity,
                         rec_date_list.sales_return_quantity,
                         rec_date_list.damage_quantity,
                         COALESCE (w_product_available_stock, 0),
                         COALESCE (w_product_purchase_rate, 0),
                         rec_date_list.stock_total_price,
                         COALESCE (w_total_purchase_balance, 0.00),
                         rec_date_list.sales_total_price,
                         COALESCE (w_total_sales_balance, 0.00),
                         rec_date_list.sales_return_total_price,
                         rec_date_list.damage_amount,
                         rec_date_list.stock_return_total_price,
                         rec_date_list.cost_of_good_sold,
                         COALESCE (w_cost_of_good_sold_balance, 0.00),
                         0,
                         rec_date_list.sales_discount_amount,
                         'system',
                         current_timestamp);
         END LOOP;
      END LOOP;

      UPDATE sales_products_inventory_status
         SET inv_balance_upto_date = w_calculate_date,
             is_balance_updated = TRUE
       WHERE branch_code = p_branch_code 
       AND product_id = p_product_code;
   END LOOP;

   o_status := 'S';
   o_errm := '';
EXCEPTION
   WHEN OTHERS
   THEN
      IF w_status = 'E'
      THEN
         o_status := w_status;
         o_errm := w_errm;
      ELSE
         o_status := 'E';
         o_errm := SQLERRM;
      END IF;
END;
$$;


ALTER FUNCTION public.fn_sales_product_inventory_hist(p_branch_code integer, p_product_code character, OUT o_status character, OUT o_errm character) OWNER TO postgres;

--
-- Name: fn_sales_sales_cancel(integer, character, character, character); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_sales_sales_cancel(p_branch_code integer, p_app_user_id character, p_invoice_number character, p_cancel_reason character, OUT o_status character, OUT o_errm character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_status                  VARCHAR;
   w_errm                    VARCHAR;
   product_list              RECORD;
   product_return_list       RECORD;
   product_return_details    RECORD;
   w_sales_date              DATE;
   w_tran_batch_number       INTEGER;
   w_sales_status            VARCHAR;
   w_parent_delar            INTEGER;
   w_counter                 INTEGER;
   w_last_balance_update     DATE;
   w_last_transaction_date   DATE;
BEGIN
   BEGIN
      SELECT invoice_date, tran_batch_number, status
        INTO STRICT w_sales_date, w_tran_batch_number, w_sales_status
        FROM sales_sales_master
       WHERE invoice_number = p_invoice_number;
   EXCEPTION
      WHEN NO_DATA_FOUND
      THEN
         RAISE EXCEPTION
         USING MESSAGE = 'Invalid Invoice ' || p_invoice_number || ' Number !';
   END;

   IF w_sales_status = 'C'
   THEN
      w_status := 'E';
      w_errm := 'Invoice already canceled!';
      RAISE EXCEPTION USING MESSAGE = w_errm;
   END IF;

   BEGIN
      SELECT count (emi_reference_no)
        INTO w_counter
        FROM sales_emi_setup
       WHERE emi_reference_no = p_invoice_number AND emi_cancel_by IS NULL;
   END;

   IF w_counter > 0
   THEN
      w_status := 'E';
      w_errm := 'EMI Setup Exist for This Invoice!';
      RAISE EXCEPTION USING MESSAGE = w_errm;
   END IF;


   FOR product_list
      IN (SELECT s.*, m.invoice_date
            FROM sales_sales_details s, sales_sales_master m
           WHERE     m.invoice_number = p_invoice_number
                 AND s.invoice_number = m.invoice_number
                 AND m.branch_code = p_branch_code)
   LOOP
      w_last_transaction_date := product_list.invoice_date;

      SELECT inv_balance_upto_date
       INTO STRICT w_last_balance_update
       FROM sales_products_inventory_status
      WHERE     product_id = product_list.product_id
            AND branch_code = p_branch_code;

      IF w_last_transaction_date < w_last_balance_update
      THEN
         w_last_balance_update := w_last_transaction_date;
      ELSE
         w_last_balance_update := w_last_balance_update;
      END IF;

      IF w_last_transaction_date > w_last_transaction_date
      THEN
         w_last_transaction_date := w_last_transaction_date;
      ELSE
         w_last_transaction_date := w_last_transaction_date;
      END IF;

      UPDATE sales_products_inventory_status
         SET total_sales_amount =
                  total_sales_amount
                - (product_list.total_price - product_list.discount_amount),
             product_total_sales =
                product_total_sales - product_list.quantity,
             product_available_stock =
                product_available_stock + product_list.quantity,
             inv_balance_upto_date = w_last_balance_update,
             is_balance_updated = FALSE
       WHERE     product_id = product_list.product_id
             AND branch_code = p_branch_code;

      UPDATE sales_products
         SET total_sales_amount =
                  total_sales_amount
                - (product_list.total_price - product_list.discount_amount),
             product_total_sales =
                product_total_sales - product_list.quantity,
             product_available_stock =
                product_available_stock + product_list.quantity
       WHERE product_id = product_list.product_id;
   END LOOP;

   BEGIN
      SELECT *
        INTO w_status, w_errm
        FROM fn_finance_post_tran_cancel (p_branch_code,
                                          p_app_user_id,
                                          w_sales_date,
                                          w_tran_batch_number,
                                          p_cancel_reason);

      IF w_status = 'E'
      THEN
         RAISE EXCEPTION USING MESSAGE = w_errm;
      ELSE
         BEGIN
            UPDATE sales_sales_master
               SET STATUS = 'C',
                   cancel_by = p_app_user_id,
                   cancel_on = current_timestamp
             WHERE     invoice_number = p_invoice_number
                   AND branch_code = p_branch_code;

            UPDATE sales_sales_details
               SET STATUS = 'C'
             WHERE     invoice_number = p_invoice_number
                   AND branch_code = p_branch_code;
         END;
      END IF;
   END;

   o_status := 'S';
   o_errm := '';
EXCEPTION
   WHEN OTHERS
   THEN
      IF w_status = 'E'
      THEN
         o_status := w_status;
         o_errm := w_errm;
      ELSE
         o_status := 'E';
         o_errm := SQLERRM;
      END IF;
END;
$$;


ALTER FUNCTION public.fn_sales_sales_cancel(p_branch_code integer, p_app_user_id character, p_invoice_number character, p_cancel_reason character, OUT o_status character, OUT o_errm character) OWNER TO postgres;

--
-- Name: fn_sales_sales_post(integer, character, character, character, character, character, character, character, character, character, numeric, numeric, character, character, character, character, numeric, numeric, date, numeric, numeric); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_sales_sales_post(p_branch_code integer, p_center_code character, p_app_user_id character, p_invoice_number character, p_customer_phone character, p_customer_id character, p_customer_name character, p_customer_address character, p_account_number character, p_employee_id character, p_pay_amount numeric, p_invoice_discount numeric, p_tran_type_code character, p_bill_receive_gl character, p_bill_due_gl character, p_payment_document character, p_discount_rate numeric, p_discount_amount numeric, p_invoice_date date, p_latitude numeric, p_longitude numeric, OUT o_status character, OUT o_errm character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_error_message              VARCHAR;
   w_batch_number               INTEGER;
   w_check                      BOOLEAN;
   w_account_number             VARCHAR := '0';
   w_transaction_date           DATE;
   product_list                 RECORD;
   w_tran_gl_code               VARCHAR := '0';
   w_cash_transaction           BOOLEAN;
   w_total_leg                  INTEGER;
   w_total_debit_amount         NUMERIC (22, 2) := 0;
   w_total_credit_amount        NUMERIC (22, 2) := 0;
   w_account_banalce            NUMERIC (22, 2) := 0;
   w_credit_limit               NUMERIC (22, 2) := 0;
   w_serial_no                  INTEGER := 0;
   w_product_total_stock        INTEGER := 0;
   w_product_total_sales        INTEGER := 0;
   w_product_available_stock    INTEGER := 0;
   w_product_last_stock_date    DATE;
   w_product_last_sale_date     DATE;
   w_product_last_return_date   DATE;
   w_product_total_returned     INTEGER := 0;
   w_total_purchase_amount      NUMERIC (22, 2) := 0.00;
   w_total_return_amount        NUMERIC (22, 2) := 0.00;
   w_total_sales_amount         NUMERIC (22, 2) := 0.00;
   w_product_total_damage       INTEGER := 0;
   w_total_return_damage        NUMERIC (22, 2) := 0.00;
   w_last_order_date            DATE;
   w_total_order_quantity       INTEGER := 0;
   w_total_bill_amount          NUMERIC (22, 2) := 0.00;
   w_bill_amount                NUMERIC (22, 2) := 0.00;
   w_due_amount                 NUMERIC (22, 2) := 0.00;
   w_advance_pay                NUMERIC (22, 2) := 0.00;
   w_invoice_discount_gl        VARCHAR;
   w_status                     VARCHAR;
   w_errm                       VARCHAR;
   w_product_name               VARCHAR;
   w_tran_debit_account_type    VARCHAR;
   w_last_balance_update        DATE;
   w_last_transaction_date      DATE;
BEGIN
   BEGIN
      SELECT credit_limit, account_balance
        INTO w_credit_limit, w_account_banalce
        FROM finance_accounts_balance b
       WHERE b.account_number = p_account_number;
   END;

   BEGIN
      SELECT invoice_discount_gl
        INTO STRICT w_invoice_discount_gl
        FROM sales_application_settings;
   EXCEPTION
      WHEN NO_DATA_FOUND
      THEN
         RAISE EXCEPTION USING MESSAGE = 'Discount Ledger is Not Configured!';
   END;

   FOR product_list
      IN (  SELECT s.invoice_number,
                   s.product_id,
                   s.serial_no,
                   s.service_type,
                   s.service_start_date,
                   s.service_end_date,
                   s.service_card_no,
                   s.product_price,
                   s.quantity,
                   s.total_price,
                     (s.total_price - (p.product_current_rate * s.quantity))
                   - discount_amount profit_amount,
                   p.product_current_rate purchase_rate,
                   s.discount_rate,
                   s.discount_amount,
                   s.status,
                   s.comments,
                   s.details_branch_code branch_code,
                   s.app_user_id,
                   s.app_data_time
              FROM sales_sales_details_temp s, sales_products p
             WHERE     p.product_id = s.product_id
                   AND s.app_user_id = p_app_user_id
          ORDER BY serial_no)
   LOOP
      BEGIN
         w_total_order_quantity :=
            w_total_order_quantity + product_list.quantity;
         w_serial_no := w_serial_no + 1;
         w_total_bill_amount :=
            w_total_bill_amount + product_list.total_price;
         w_bill_amount :=
              w_bill_amount
            + product_list.total_price
            - product_list.discount_amount;

         INSERT INTO sales_sales_details (invoice_number,
                                          center_code,
                                          client_id,
                                          product_id,
                                          serial_no,
                                          service_type,
                                          service_start_date,
                                          service_end_date,
                                          service_card_no,
                                          purchase_rate,
                                          product_price,
                                          quantity,
                                          returned_quantity,
                                          total_price,
                                          profit_amount,
                                          discount_rate,
                                          discount_amount,
                                          status,
                                          comments,
                                          branch_code,
                                          app_user_id,
                                          app_data_time)
              VALUES (p_invoice_number,
                      COALESCE (p_center_code,'0'),
                      p_customer_id,
                      product_list.product_id,
                      w_serial_no,
                      product_list.service_type,
                      product_list.service_start_date,
                      product_list.service_end_date,
                      product_list.service_card_no,
                      product_list.purchase_rate,
                      product_list.product_price,
                      product_list.quantity,
                      0,
                      product_list.total_price,
                      product_list.profit_amount,
                      product_list.discount_rate,
                      product_list.discount_amount,
                      'I',
                      product_list.comments,
                      p_branch_code,
                      product_list.app_user_id,
                      current_timestamp);
      END;

      BEGIN
         SELECT product_available_stock,
                inv_balance_upto_date,
                COALESCE (last_sale_date, p_invoice_date) last_sale_date
           INTO w_product_available_stock,
                w_last_balance_update,
                w_last_transaction_date
           FROM sales_products_inventory_status
          WHERE     product_id = product_list.product_id
                AND branch_code = p_branch_code;

         SELECT product_name
           INTO w_product_name
           FROM sales_products
          WHERE product_id = product_list.product_id;
      END;

      IF w_product_available_stock - product_list.quantity < 0
      THEN
         w_status := 'E';
         w_errm := 'Product ' || w_product_name || ' Out of Stock!';
         RAISE EXCEPTION USING MESSAGE = w_errm;
      END IF;

      w_last_balance_update := LEAST (w_last_balance_update, p_invoice_date);
      w_last_transaction_date :=
         GREATEST (w_last_transaction_date, p_invoice_date);

      UPDATE sales_products_inventory_status
         SET total_sales_amount =
                  total_sales_amount
                + (product_list.total_price - product_list.discount_amount),
             product_total_sales =
                product_total_sales + product_list.quantity,
             product_available_stock =
                product_available_stock - product_list.quantity,
             cost_of_good_sold =
                  cost_of_good_sold
                + (product_list.purchase_rate * product_list.quantity),
             last_sale_date = w_last_transaction_date,
             inv_balance_upto_date = w_last_balance_update,
             is_balance_updated = FALSE
       WHERE     product_id = product_list.product_id
             AND branch_code = p_branch_code;

      UPDATE sales_products
         SET total_sales_amount =
                  total_sales_amount
                + (product_list.total_price - product_list.discount_amount),
             product_total_sales =
                product_total_sales + product_list.quantity,
             product_available_stock =
                product_available_stock - product_list.quantity,
             product_last_sale_date = w_last_transaction_date
       WHERE product_id = product_list.product_id;
   END LOOP;

   w_due_amount := w_bill_amount - p_pay_amount;

   IF w_due_amount < 0
   THEN
      w_advance_pay := p_pay_amount - w_bill_amount;
      w_due_amount := 0;
   END IF;

   w_bill_amount :=
      COALESCE (w_bill_amount, 0) - COALESCE (p_invoice_discount, 0);

   INSERT INTO sales_sales_master (invoice_number,
                                   center_code,
                                   invoice_date,
                                   customer_id,
                                   customer_name,
                                   customer_phone,
                                   customer_address,
                                   employee_id,
                                   payment_document,
                                   tran_type_code,
                                   total_quantity,
                                   returned_quantity,
                                   returned_amount,
                                   total_bill_amount,
                                   bill_amount,
                                   pay_amount,
                                   due_amount,
                                   advance_pay,
                                   total_discount_rate,
                                   total_discount_amount,
                                   invoice_discount,
                                   status,
                                   invoice_comments,
                                   branch_code,
                                   app_user_id,
                                   app_data_time,
                                   latitude,
                                   longitude)
           VALUES (
                     p_invoice_number,
                     COALESCE (p_center_code,'0'),
                     p_invoice_date,
                     P_customer_id,
                     P_customer_name,
                     P_customer_phone,
                     p_customer_address,
                     p_employee_id,
                     p_payment_document,
                     p_tran_type_code,
                     w_total_order_quantity,
                     0,
                     0,
                     w_total_bill_amount,
                     w_bill_amount,
                     p_pay_amount,
                     w_due_amount,
                     w_advance_pay,
                     p_discount_rate,
                       COALESCE (p_discount_amount, 0)
                     + COALESCE (p_invoice_discount, 0),
                     COALESCE (p_invoice_discount, 0),
                     'I',
                     NULL,
                     p_branch_code,
                     p_app_user_id,
                     current_timestamp,
                     p_latitude,
                     p_longitude);

   BEGIN
      SELECT *
        INTO w_status, w_errm, w_batch_number
        FROM fn_sales_sales_tran_table_insert (p_branch_code,
                                               COALESCE (p_center_code,'0'),
                                               p_app_user_id,
                                               p_customer_phone,
                                               p_account_number,
                                               w_bill_amount,
                                               p_pay_amount,
                                               p_invoice_discount,
                                               p_bill_receive_gl,
                                               p_bill_due_gl,
                                               w_invoice_discount_gl,
                                               'SALES',
                                               p_tran_type_code,
                                               p_invoice_date,
                                               p_employee_id,
                                               p_invoice_number);

      IF w_status = 'E'
      THEN
         RAISE EXCEPTION USING MESSAGE = w_errm;
      END IF;
   END;

   BEGIN
      SELECT *
        INTO w_status, w_errm, w_batch_number
        FROM fn_finance_post_tran (p_branch_code,
                                   COALESCE (p_center_code,'0'),
                                   p_app_user_id,
                                   p_tran_type_code,
                                   p_invoice_date,
                                   'Sales Posting',
                                   'SALES');

      IF w_status = 'E'
      THEN
         RAISE EXCEPTION USING MESSAGE = w_errm;
      ELSE
         UPDATE sales_sales_master
            SET tran_batch_number = w_batch_number
          WHERE     invoice_number = p_invoice_number
                AND invoice_date = p_invoice_date;
      END IF;
   END;

   DELETE FROM sales_sales_details_temp s
         WHERE s.app_user_id = p_app_user_id;

   o_status := 'S';
   o_errm := '';
EXCEPTION
   WHEN OTHERS
   THEN
      IF w_status = 'E'
      THEN
         o_status := w_status;
         o_errm := w_errm;
      ELSE
         o_status := 'E';
         o_errm := SQLERRM;
      END IF;
END;
$$;


ALTER FUNCTION public.fn_sales_sales_post(p_branch_code integer, p_center_code character, p_app_user_id character, p_invoice_number character, p_customer_phone character, p_customer_id character, p_customer_name character, p_customer_address character, p_account_number character, p_employee_id character, p_pay_amount numeric, p_invoice_discount numeric, p_tran_type_code character, p_bill_receive_gl character, p_bill_due_gl character, p_payment_document character, p_discount_rate numeric, p_discount_amount numeric, p_invoice_date date, p_latitude numeric, p_longitude numeric, OUT o_status character, OUT o_errm character) OWNER TO postgres;

--
-- Name: fn_sales_sales_return(integer, character, character, date, character, integer, numeric, character, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_sales_sales_return(p_branch_code integer, p_app_user_id character, p_invoice_number character, p_invoice_date date, p_product_id character, p_returned_quantity integer, p_returned_price numeric, p_return_reason character, p_return_date date, OUT o_status character, OUT o_errm character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_status                     VARCHAR;
   w_errm                       VARCHAR;
   product_list                 RECORD;
   w_invoice_date               DATE;
   w_tran_batch_number          INTEGER;
   w_invoice_status             VARCHAR;
   w_customer_phone             VARCHAR;
   w_tran_gl_code               VARCHAR := '0';
   w_cash_gl_code               VARCHAR := '0';
   w_customer_id                VARCHAR := '0';
   w_contra_gl_code             VARCHAR := '0';
   w_account_ledger_code        VARCHAR := '0';
   w_invoice_discount_gl        VARCHAR := '0';
   w_serial_no                  INTEGER := 0;
   w_tran_amount                NUMERIC (22, 2) := 0;
   w_profitloss_amount          NUMERIC (22, 2) := 0;
   w_tran_naration              VARCHAR;
   w_debit_credit               VARCHAR;
   w_center_code                VARCHAR;
   w_total_return_amount        NUMERIC (22, 2) := 0;
   w_total_pay_amount           NUMERIC (22, 2) := 0;
   w_total_due_amount           NUMERIC (22, 2) := 0;
   w_total_discount_amount      NUMERIC (22, 2) := 0;
   w_account_number             VARCHAR := '0';
   w_client_account             VARCHAR := '0';
   w_return_voucher             VARCHAR;
   w_invoice_number             VARCHAR;
   w_batch_number               INTEGER;
   w_sql_statements             VARCHAR;
   w_counter                    INTEGER;
   w_loss_adjustment_ledger     VARCHAR;
   w_profit_adjustment_ledger   VARCHAR;
   w_last_balance_update        DATE;
   w_last_transaction_date      DATE;


   cur_all_products CURSOR FOR
      SELECT quantity quantity,
             s.purchase_rate,
             s.discount_amount,
             s.total_price total_price,
             pay_amount,
             due_amount,
             s.product_id,
             s.client_id,
             s.branch_code,
             p.product_sales_gl,
             p.product_sales_ret_gl,
             p.product_profit_gl,
             p.product_loss_gl,
             s.returned_quantity,
             s.status,
             s.purchase_rate * quantity total_purchase_amount
        FROM sales_sales_details s, sales_products p, sales_sales_master m
       WHERE     p.product_id = s.product_id
             AND s.invoice_number = m.invoice_number
             AND s.branch_code = p_branch_code
             AND s.app_user_id = p_app_user_id
             AND s.invoice_number = p_invoice_number;

   cur_products CURSOR FOR
      SELECT p_returned_quantity quantity,
             s.purchase_rate,
             s.discount_amount,
             p_returned_price total_price,
             s.product_id,
             s.client_id,
             s.branch_code,
             p.product_sales_gl,
             p.product_sales_ret_gl,
             p.product_profit_gl,
             p.product_loss_gl,
             s.returned_quantity,
             s.status,
             s.purchase_rate * p_returned_quantity total_purchase_amount
        FROM sales_sales_details s, sales_products p
       WHERE     p.product_id = s.product_id
             AND s.branch_code = p_branch_code
             AND s.app_user_id = p_app_user_id
             AND s.invoice_number = p_invoice_number
             AND s.product_id = p_product_id;
BEGIN
   BEGIN
      SELECT customer_id,
             center_code,
             invoice_date,
             tran_batch_number,
             status,
             customer_phone,
             invoice_number,
             pay_amount,
             due_amount
        INTO STRICT w_customer_id,
                    w_center_code,
                    w_invoice_date,
                    w_tran_batch_number,
                    w_invoice_status,
                    w_customer_phone,
                    w_invoice_number,
                    w_total_pay_amount,
                    w_total_due_amount
        FROM sales_sales_master
       WHERE     invoice_number = p_invoice_number
             AND branch_code = p_branch_code;
   EXCEPTION
      WHEN NO_DATA_FOUND
      THEN
         RAISE EXCEPTION USING MESSAGE = 'Invalid Invoice Number!';
   END;

   BEGIN
      SELECT DISTINCT account_number
        INTO w_client_account
        FROM finance_transaction_details
       WHERE     batch_number = w_tran_batch_number
             AND transaction_date = w_invoice_date
             AND account_number <> '0';
   EXCEPTION
      WHEN OTHERS
      THEN
         w_status := 'E';
         w_errm := SQLERRM;
         RAISE EXCEPTION USING MESSAGE = w_errm;
   END;

   BEGIN
      SELECT account_ledger_code
        INTO STRICT w_account_ledger_code
        FROM finance_accounts_balance
       WHERE account_number = w_client_account;
   EXCEPTION
      WHEN NO_DATA_FOUND
      THEN
         RAISE EXCEPTION
         USING MESSAGE = 'Invalid Account Number ' || w_account_number || '!';
   END;

   BEGIN
      SELECT count (emi_reference_no)
        INTO w_counter
        FROM sales_emi_setup
       WHERE emi_reference_no = p_invoice_number AND emi_cancel_by IS NULL;
   END;

   IF w_counter > 0
   THEN
      w_status := 'E';
      w_errm := 'EMI Setup Exist for This Invoice!';
      RAISE EXCEPTION USING MESSAGE = w_errm;
   END IF;

   w_return_voucher :=
      fn_get_inventory_number (106,
                               1,
                               'IRT',
                               'Invoice Return Number');

   IF w_invoice_status = 'C'
   THEN
      w_status := 'E';
      w_errm := 'You can not return the canceled invoice!';
      RAISE EXCEPTION USING MESSAGE = w_errm;
   END IF;

   IF w_invoice_status = 'R'
   THEN
      w_status := 'E';
      w_errm := 'Invoice already returned!';
      RAISE EXCEPTION USING MESSAGE = w_errm;
   END IF;

   IF p_product_id != 'ALL'
   THEN
      OPEN cur_products;
   ELSE
      OPEN cur_all_products;
   END IF;

   LOOP
      IF p_product_id != 'ALL'
      THEN
         FETCH cur_products INTO product_list;
      ELSE
         FETCH cur_all_products INTO product_list;
      END IF;

      EXIT WHEN NOT FOUND;

      IF product_list.status = 'R'
      THEN
         w_status := 'E';
         w_errm := 'Invoice already returned!';
         RAISE EXCEPTION USING MESSAGE = w_errm;
      END IF;

      w_tran_amount := product_list.total_purchase_amount;

      IF w_tran_amount > 0
      THEN
         w_tran_gl_code := product_list.product_sales_gl;
         w_tran_naration := 'Invoice Return for ' || p_invoice_number;
         w_serial_no := w_serial_no + 1;
         w_debit_credit := 'D';
         w_account_number := '0';
         w_contra_gl_code := w_account_ledger_code;

         INSERT INTO finance_transaction_table (branch_code,
                                                center_code,
                                                transaction_date,
                                                batch_serial,
                                                account_number,
                                                tran_gl_code,
                                                contra_gl_code,
                                                tran_debit_credit,
                                                tran_type,
                                                tran_amount,
                                                available_balance,
                                                tran_person_phone,
                                                tran_person_name,
                                                tran_document_prefix,
                                                tran_document_number,
                                                tran_sign_verified,
                                                system_posted_tran,
                                                transaction_narration,
                                                app_user_id,
                                                app_data_time)
              VALUES (p_branch_code,
                      w_center_code,
                      p_return_date,
                      w_serial_no,
                      w_account_number,
                      w_tran_gl_code,
                      w_contra_gl_code,
                      w_debit_credit,
                      'SALES_RETURN',
                      w_tran_amount,
                      0,
                      w_customer_phone,
                      '',
                      NULL,
                      p_invoice_number,
                      FALSE,
                      TRUE,
                      w_tran_naration,
                      p_app_user_id,
                      current_timestamp);

         --w_tran_gl_code := product_list.product_sales_ret_gl;
         w_serial_no := w_serial_no + 1;
         w_debit_credit := 'C';
         w_account_number := w_client_account;
         w_tran_gl_code := '0';
         w_contra_gl_code := product_list.product_sales_gl;
         w_tran_amount :=
            product_list.total_price - product_list.discount_amount;

         INSERT INTO finance_transaction_table (branch_code,
                                                center_code,
                                                transaction_date,
                                                batch_serial,
                                                account_number,
                                                tran_gl_code,
                                                contra_gl_code,
                                                tran_debit_credit,
                                                tran_type,
                                                tran_amount,
                                                available_balance,
                                                tran_person_phone,
                                                tran_person_name,
                                                tran_document_prefix,
                                                tran_document_number,
                                                tran_sign_verified,
                                                system_posted_tran,
                                                transaction_narration,
                                                app_user_id,
                                                app_data_time)
              VALUES (p_branch_code,
                      w_center_code,
                      p_return_date,
                      w_serial_no,
                      w_account_number,
                      w_tran_gl_code,
                      w_contra_gl_code,
                      w_debit_credit,
                      'SALES_RETURN',
                      w_tran_amount,
                      0,
                      w_customer_phone,
                      '',
                      NULL,
                      p_invoice_number,
                      FALSE,
                      TRUE,
                      w_tran_naration,
                      p_app_user_id,
                      current_timestamp);
      END IF;

      w_profitloss_amount :=
         (product_list.total_price - product_list.total_purchase_amount);

      w_total_discount_amount :=
         w_total_discount_amount + product_list.discount_amount;

      IF w_profitloss_amount > 0
      THEN
         w_tran_gl_code := product_list.product_profit_gl;
         w_tran_amount := w_profitloss_amount;
         w_tran_naration := 'Profit Reverse for Invoice ' || p_invoice_number;
         w_serial_no := w_serial_no + 1;
         w_debit_credit := 'D';
      ELSIF w_profitloss_amount < 0
      THEN
         w_tran_gl_code := product_list.product_loss_gl;
         w_tran_amount := abs (w_profitloss_amount);
         w_tran_naration := 'Loss Reverse for Invoice ' || p_invoice_number;
         w_serial_no := w_serial_no + 1;
         w_debit_credit := 'C';
      ELSE
         w_tran_amount = 0;
      END IF;

      IF w_tran_amount > 0
      THEN
         INSERT INTO finance_transaction_table (branch_code,
                                                center_code,
                                                transaction_date,
                                                batch_serial,
                                                account_number,
                                                tran_gl_code,
                                                contra_gl_code,
                                                tran_debit_credit,
                                                tran_type,
                                                tran_amount,
                                                available_balance,
                                                tran_person_phone,
                                                tran_person_name,
                                                tran_document_prefix,
                                                tran_document_number,
                                                tran_sign_verified,
                                                system_posted_tran,
                                                transaction_narration,
                                                app_user_id,
                                                app_data_time)
              VALUES (p_branch_code,
                      w_center_code,
                      p_return_date,
                      w_serial_no,
                      '0',
                      w_tran_gl_code,
                      w_contra_gl_code,
                      w_debit_credit,
                      'SALES_RETURN',
                      w_tran_amount,
                      0,
                      w_customer_phone,
                      '',
                      NULL,
                      p_invoice_number,
                      FALSE,
                      TRUE,
                      w_tran_naration,
                      p_app_user_id,
                      current_timestamp);
      END IF;

      INSERT INTO sales_sales_return_details (sales_invoice,
                                              client_id,
                                              sales_date,
                                              product_id,
                                              return_invoice,
                                              return_date,
                                              status,
                                              tran_type_code,
                                              tran_batch_number,
                                              returned_quantity,
                                              return_amount,
                                              purchase_value,
                                              return_reason,
                                              branch_code,
                                              center_code,
                                              app_user_id,
                                              app_data_time)
           VALUES (p_invoice_number,
                   product_list.client_id,
                   w_invoice_date,
                   product_list.product_id,
                   w_return_voucher,
                   p_return_date,
                   'R',
                   NULL,
                   NULL,
                   product_list.quantity,
                   product_list.total_price,
                   product_list.total_purchase_amount,
                   p_return_reason,
                   p_branch_code,
                   w_center_code,
                   p_app_user_id,
                   current_timestamp);

      SELECT inv_balance_upto_date,
             COALESCE (last_sales_return_date, p_return_date) last_sales_return_date
        INTO STRICT w_last_balance_update, w_last_transaction_date
        FROM sales_products_inventory_status
       WHERE     product_id = product_list.product_id
             AND branch_code = p_branch_code;

      w_last_balance_update := LEAST (w_last_balance_update, p_return_date);
      w_last_transaction_date :=
         GREATEST (w_last_transaction_date, p_return_date);

      UPDATE sales_products_inventory_status
         SET product_available_stock =
                  product_available_stock
                + (product_list.quantity - product_list.returned_quantity),
             total_sales_amount =
                total_sales_amount - product_list.total_price,
             product_total_sales =
                  product_total_sales
                - (product_list.quantity - product_list.returned_quantity),
             cost_of_good_sold =
                cost_of_good_sold - product_list.total_purchase_amount,
             total_sales_return =
                total_sales_return + product_list.returned_quantity,
             last_sales_return_date = w_last_transaction_date,
             inv_balance_upto_date = w_last_balance_update,
             is_balance_updated = FALSE
       WHERE     product_id = product_list.product_id
             AND branch_code = p_branch_code;

      UPDATE sales_products
         SET product_available_stock =
                  product_available_stock
                + (product_list.quantity - product_list.returned_quantity),
             total_sales_amount =
                total_sales_amount - product_list.total_price,
             product_total_sales =
                  product_total_sales
                - (product_list.quantity - product_list.returned_quantity)
       WHERE product_id = product_list.product_id;

      UPDATE sales_sales_details
         SET returned_quantity =
                  returned_quantity
                + (product_list.quantity - product_list.returned_quantity),
             STATUS =
                (CASE
                    WHEN quantity = product_list.quantity THEN 'R'
                    ELSE 'P'
                 END)
       WHERE     invoice_number = p_invoice_number
             AND branch_code = p_branch_code
             AND product_id = product_list.product_id;

      BEGIN
         UPDATE sales_sales_master
            SET STATUS = 'P',
                returned_quantity =
                     returned_quantity
                   + (product_list.quantity - product_list.returned_quantity),
                returned_amount = returned_amount + product_list.total_price
          WHERE     invoice_number = p_invoice_number
                AND branch_code = p_branch_code;
      END;
   END LOOP;

   IF w_total_discount_amount > 0
   THEN
      BEGIN
         BEGIN
            SELECT invoice_discount_gl
              INTO STRICT w_invoice_discount_gl
              FROM sales_application_settings;
         EXCEPTION
            WHEN NO_DATA_FOUND
            THEN
               RAISE EXCEPTION
               USING MESSAGE = 'Discount Ledger is Not Configured!';
         END;

         w_debit_credit := 'C';
         w_tran_amount := w_total_discount_amount;
         w_tran_naration := 'Discount Reverse for ' || p_invoice_number;
         w_serial_no := w_serial_no + 1;
         w_tran_gl_code := w_invoice_discount_gl;
         w_contra_gl_code := '0';

         INSERT INTO finance_transaction_table (branch_code,
                                                center_code,
                                                transaction_date,
                                                batch_serial,
                                                account_number,
                                                tran_gl_code,
                                                contra_gl_code,
                                                tran_debit_credit,
                                                tran_type,
                                                tran_amount,
                                                available_balance,
                                                tran_person_phone,
                                                tran_person_name,
                                                tran_document_prefix,
                                                tran_document_number,
                                                tran_sign_verified,
                                                system_posted_tran,
                                                transaction_narration,
                                                app_user_id,
                                                app_data_time)
              VALUES (p_branch_code,
                      w_center_code,
                      p_return_date,
                      w_serial_no,
                      '0',
                      w_tran_gl_code,
                      w_contra_gl_code,
                      w_debit_credit,
                      'SALES_RETURN',
                      w_tran_amount,
                      0,
                      w_customer_phone,
                      '',
                      NULL,
                      p_invoice_number,
                      FALSE,
                      TRUE,
                      w_tran_naration,
                      p_app_user_id,
                      current_timestamp);
      END;
   END IF;

   BEGIN
      SELECT *
        INTO w_status, w_errm, w_batch_number
        FROM fn_finance_post_tran (p_branch_code,
                                   w_center_code,
                                   p_app_user_id,
                                   'SALES_RETURN',
                                   p_return_date,
                                   p_return_reason,
                                   'SALES_RETURN');

      IF w_status = 'E'
      THEN
         RAISE EXCEPTION USING MESSAGE = w_errm;
      ELSE
         BEGIN
            UPDATE sales_sales_master
               SET STATUS =
                      (CASE
                          WHEN total_quantity = returned_quantity THEN 'R'
                          ELSE 'P'
                       END)
             WHERE     invoice_number = p_invoice_number
                   AND branch_code = p_branch_code;
         END;

         BEGIN
            UPDATE sales_sales_return_details
               SET tran_batch_number = w_batch_number
             WHERE     return_invoice = w_return_voucher
                   AND branch_code = p_branch_code;
         END;
      END IF;
   END;

   o_status := 'S';
   o_errm := '';
EXCEPTION
   WHEN OTHERS
   THEN
      IF w_status = 'E'
      THEN
         o_status := w_status;
         o_errm := w_errm;
      ELSE
         o_status := 'E';
         o_errm := SQLERRM;
      END IF;
END;
$$;


ALTER FUNCTION public.fn_sales_sales_return(p_branch_code integer, p_app_user_id character, p_invoice_number character, p_invoice_date date, p_product_id character, p_returned_quantity integer, p_returned_price numeric, p_return_reason character, p_return_date date, OUT o_status character, OUT o_errm character) OWNER TO postgres;

--
-- Name: fn_sales_sales_tran_table_insert(integer, character, character, character, character, numeric, numeric, numeric, character, character, character, character, character, date, character, character); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_sales_sales_tran_table_insert(p_branch_code integer, p_center_code character, p_app_user_id character, p_customer_phone character, p_account_number character, p_bill_amount numeric, p_pay_amount numeric, p_discount_amount numeric, p_bill_receive_gl character, p_bill_due_gl character, p_discount_ledger character, p_transaction_type character, p_payment_type character, p_transaction_date date, p_employee_id character, p_document_number character, OUT o_status character, OUT o_errm character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_error_message             VARCHAR;
   w_debit_credit              VARCHAR;
   w_batch_serial              INTEGER;
   w_tran_amount               NUMERIC (22, 2) := 0;
   w_total_debit_amount        NUMERIC (22, 2) := 0;
   w_total_credit_amount       NUMERIC (22, 2) := 0;
   w_total_order_amount        NUMERIC (22, 2) := 0;
   w_total_discount_amount     NUMERIC (22, 2) := 0;
   w_tran_naration             VARCHAR;
   tran_list                   RECORD;
   w_tran_gl_code              VARCHAR := '0';
   w_contra_gl_code            VARCHAR := '0';
   w_cash_contra_gl_code       VARCHAR := '0';
   w_serial_no                 INTEGER := 0;
   w_status                    VARCHAR;
   w_errm                      VARCHAR;
   w_tran_debit_account_type   VARCHAR;
   w_client_id                 VARCHAR;
   w_account_number            VARCHAR;
BEGIN
   IF p_transaction_type IN ('SALES', 'ORDER')
   THEN
      w_debit_credit := 'C';
   ELSE
      w_debit_credit := 'C';
   END IF;

   w_total_discount_amount := COALESCE (p_discount_amount, 0);

   FOR tran_list
      IN (SELECT *
          FROM (  SELECT sum (tran_amount) tran_amount,
                         sum (product_actual_profit) product_actual_profit,
                         sum (discount_amount) discount_amount,
                         sum (purchase_tran_amount) purchase_tran_amount,
                         tran_gl_code,
                         product_profit_gl,
                         product_loss_gl,
                         tran_naration
                    FROM (  SELECT (p.product_current_rate * s.quantity)
                                      purchase_tran_amount,
                                   (s.total_price)
                                      tran_amount,
                                   s.discount_amount
                                      discount_amount,
                                   (CASE
                                       WHEN p_transaction_type = 'STOCK'
                                       THEN
                                          product_stock_gl
                                       WHEN p_transaction_type = 'SALES'
                                       THEN
                                          product_sales_gl
                                       WHEN p_transaction_type = 'ORDER'
                                       THEN
                                          product_order_gl
                                       WHEN p_transaction_type = 'PROFIT'
                                       THEN
                                          product_profit_gl
                                       WHEN p_transaction_type = 'LOSS'
                                       THEN
                                          product_loss_gl
                                    END)
                                      tran_gl_code,
                                   substr (
                                         initcap (p_transaction_type)
                                      || ' for '
                                      || p.product_name,
                                      0,
                                      100)
                                      tran_naration,
                                     (  s.total_price
                                      - (p.product_current_rate * s.quantity))
                                   - discount_amount
                                      profit_without_discount,
                                   (  s.total_price
                                    - (p.product_current_rate * s.quantity))
                                      product_actual_profit,
                                   product_profit_gl,
                                   product_loss_gl
                              FROM sales_sales_details_temp s, sales_products p
                             WHERE     p.product_id = s.product_id
                                   AND s.app_user_id = p_app_user_id
                          ORDER BY s.id) o
                GROUP BY tran_gl_code,
                         tran_naration,
                         product_profit_gl,
                         product_loss_gl) s)
   LOOP
      ---- Product Sales Leg

      w_tran_gl_code := tran_list.tran_gl_code;
      w_cash_contra_gl_code := w_tran_gl_code;
      w_debit_credit := 'C';
      w_tran_amount := tran_list.purchase_tran_amount;

      -- RAISE EXCEPTION USING MESSAGE = tran_list.purchase_tran_amount;

      w_tran_naration := tran_list.tran_naration;
      w_serial_no := w_serial_no + 1;

      w_total_discount_amount :=
         w_total_discount_amount + tran_list.discount_amount;

      IF p_pay_amount = p_bill_amount
      THEN
         w_contra_gl_code := p_bill_receive_gl;
      END IF;

      IF w_tran_amount > 0
      THEN
         INSERT INTO finance_transaction_table (branch_code,
                                                center_code,
                                                transaction_date,
                                                batch_serial,
                                                account_number,
                                                tran_gl_code,
                                                contra_gl_code,
                                                tran_debit_credit,
                                                tran_type,
                                                tran_amount,
                                                available_balance,
                                                tran_person_phone,
                                                tran_person_name,
                                                tran_document_prefix,
                                                tran_document_number,
                                                tran_sign_verified,
                                                system_posted_tran,
                                                transaction_narration,
                                                app_user_id,
                                                app_data_time)
              VALUES (p_branch_code,
                      p_center_code,
                      p_transaction_date,
                      w_serial_no,
                      '0',
                      w_tran_gl_code,
                      w_contra_gl_code,
                      w_debit_credit,
                      p_transaction_type,
                      w_tran_amount,
                      0,
                      p_employee_id,
                      '',
                      NULL,
                      p_document_number,
                      FALSE,
                      TRUE,
                      w_tran_naration,
                      p_app_user_id,
                      current_timestamp);
      END IF;

      ---- Product Profit/Loss Leg

      IF tran_list.product_actual_profit > 0
      THEN
         w_tran_gl_code := tran_list.product_profit_gl;
         w_tran_amount := tran_list.product_actual_profit;
         w_tran_naration :=
            'Profit Posting for Invoice ' || p_document_number;
         w_serial_no := w_serial_no + 1;
         w_debit_credit := 'C';
      ELSIF tran_list.product_actual_profit < 0
      THEN
         w_tran_gl_code := tran_list.product_loss_gl;
         w_tran_amount := abs (tran_list.product_actual_profit);
         w_tran_naration := 'Loss Posting for Invoice ' || p_document_number;
         w_serial_no := w_serial_no + 1;
         w_debit_credit := 'D';
      ELSE
         w_tran_amount = 0;
      END IF;

      IF w_tran_amount > 0
      THEN
         INSERT INTO finance_transaction_table (branch_code,
                                                center_code,
                                                transaction_date,
                                                batch_serial,
                                                account_number,
                                                tran_gl_code,
                                                contra_gl_code,
                                                tran_debit_credit,
                                                tran_type,
                                                tran_amount,
                                                available_balance,
                                                tran_person_phone,
                                                tran_person_name,
                                                tran_document_prefix,
                                                tran_document_number,
                                                tran_sign_verified,
                                                system_posted_tran,
                                                transaction_narration,
                                                app_user_id,
                                                app_data_time)
              VALUES (p_branch_code,
                      p_center_code,
                      p_transaction_date,
                      w_serial_no,
                      '0',
                      w_tran_gl_code,
                      w_contra_gl_code,
                      w_debit_credit,
                      p_transaction_type,
                      w_tran_amount,
                      0,
                      p_employee_id,
                      '',
                      NULL,
                      p_document_number,
                      FALSE,
                      TRUE,
                      w_tran_naration,
                      p_app_user_id,
                      current_timestamp);
      END IF;
   END LOOP;

   IF w_total_discount_amount > 0
   THEN
      BEGIN
         w_debit_credit := 'D';
         w_tran_amount := w_total_discount_amount;
         w_tran_naration :=
            'Discount for ' || p_transaction_type || ' ' || p_document_number;
         w_serial_no := w_serial_no + 1;
         w_tran_gl_code := p_discount_ledger;
         w_contra_gl_code := '0';

         INSERT INTO finance_transaction_table (branch_code,
                                                center_code,
                                                transaction_date,
                                                batch_serial,
                                                account_number,
                                                tran_gl_code,
                                                contra_gl_code,
                                                tran_debit_credit,
                                                tran_type,
                                                tran_amount,
                                                available_balance,
                                                tran_person_phone,
                                                tran_person_name,
                                                tran_document_prefix,
                                                tran_document_number,
                                                tran_sign_verified,
                                                system_posted_tran,
                                                transaction_narration,
                                                app_user_id,
                                                app_data_time)
              VALUES (p_branch_code,
                      p_center_code,
                      p_transaction_date,
                      w_serial_no,
                      '0',
                      w_tran_gl_code,
                      w_contra_gl_code,
                      w_debit_credit,
                      p_transaction_type,
                      w_tran_amount,
                      0.00,
                      p_customer_phone,
                      NULL,
                      NULL,
                      p_document_number,
                      FALSE,
                      TRUE,
                      w_tran_naration,
                      p_app_user_id,
                      current_timestamp);
      END;
   END IF;

   -- cash debit

   IF p_pay_amount > 0
   THEN
      BEGIN
         w_debit_credit := 'D';
         w_tran_amount := p_pay_amount;
         w_tran_naration :=
               'Payment Receive for '
            || p_transaction_type
            || ' '
            || p_document_number;
         w_serial_no := w_serial_no + 1;

         IF CHAR_LENGTH (w_tran_debit_account_type) > 0
         THEN
            w_account_number := p_account_number;
            w_tran_gl_code := '0';
         ELSE
            w_tran_gl_code := p_bill_receive_gl;
            w_account_number := '0';
            w_contra_gl_code := w_cash_contra_gl_code;
         END IF;

         --RAISE EXCEPTION USING MESSAGE = p_pay_amount||' TY '||p_payment_type||' AC '||w_account_number;

         INSERT INTO finance_transaction_table (branch_code,
                                                center_code,
                                                transaction_date,
                                                batch_serial,
                                                account_number,
                                                tran_gl_code,
                                                contra_gl_code,
                                                tran_debit_credit,
                                                tran_type,
                                                tran_amount,
                                                available_balance,
                                                tran_person_phone,
                                                tran_person_name,
                                                tran_document_prefix,
                                                tran_document_number,
                                                tran_sign_verified,
                                                system_posted_tran,
                                                transaction_narration,
                                                app_user_id,
                                                app_data_time)
              VALUES (p_branch_code,
                      p_center_code,
                      p_transaction_date,
                      w_serial_no,
                      w_account_number,
                      w_tran_gl_code,
                      w_contra_gl_code,
                      w_debit_credit,
                      p_transaction_type,
                      w_tran_amount,
                      0.00,
                      p_customer_phone,
                      NULL,
                      NULL,
                      p_document_number,
                      FALSE,
                      TRUE,
                      w_tran_naration,
                      p_app_user_id,
                      current_timestamp);
      END;
   END IF;

   IF p_pay_amount > 0
   THEN
      BEGIN
         w_debit_credit := 'C';
         w_tran_amount := p_pay_amount;
         w_tran_naration :=
               'Payment Receive for '
            || p_transaction_type
            || ' '
            || p_document_number;
         w_serial_no := w_serial_no + 1;

         INSERT INTO finance_transaction_table (branch_code,
                                                center_code,
                                                transaction_date,
                                                batch_serial,
                                                account_number,
                                                tran_gl_code,
                                                contra_gl_code,
                                                tran_debit_credit,
                                                tran_type,
                                                tran_amount,
                                                available_balance,
                                                tran_person_phone,
                                                tran_person_name,
                                                tran_document_prefix,
                                                tran_document_number,
                                                tran_sign_verified,
                                                system_posted_tran,
                                                transaction_narration,
                                                app_user_id,
                                                app_data_time)
              VALUES (p_branch_code,
                      p_center_code,
                      p_transaction_date,
                      w_serial_no,
                      p_account_number,
                      '0',
                      w_contra_gl_code,
                      w_debit_credit,
                      p_transaction_type,
                      w_tran_amount,
                      0.00,
                      p_customer_phone,
                      NULL,
                      NULL,
                      p_document_number,
                      FALSE,
                      TRUE,
                      w_tran_naration,
                      p_app_user_id,
                      current_timestamp);
      END;
   END IF;

   IF p_bill_amount > 0
   THEN
      BEGIN
         w_debit_credit := 'D';
         w_tran_amount := p_bill_amount;
         w_tran_naration :=
               'Bill Payment for Purchase '
            || p_transaction_type
            || ' '
            || p_document_number;
         w_serial_no = w_serial_no + 1;

         INSERT INTO finance_transaction_table (branch_code,
                                                center_code,
                                                transaction_date,
                                                batch_serial,
                                                account_number,
                                                tran_gl_code,
                                                contra_gl_code,
                                                tran_debit_credit,
                                                tran_type,
                                                tran_amount,
                                                available_balance,
                                                tran_person_phone,
                                                tran_person_name,
                                                tran_document_prefix,
                                                tran_document_number,
                                                tran_sign_verified,
                                                system_posted_tran,
                                                transaction_narration,
                                                app_user_id,
                                                app_data_time)
              VALUES (p_branch_code,
                      p_center_code,
                      p_transaction_date,
                      w_serial_no,
                      p_account_number,
                      '0',
                      w_contra_gl_code,
                      w_debit_credit,
                      p_transaction_type,
                      w_tran_amount,
                      0.00,
                      p_customer_phone,
                      NULL,
                      NULL,
                      p_document_number,
                      FALSE,
                      TRUE,
                      w_tran_naration,
                      p_app_user_id,
                      current_timestamp);
      END;
   END IF;

   o_status := 'S';
   o_errm := '';
EXCEPTION
   WHEN OTHERS
   THEN
      IF w_status = 'E'
      THEN
         o_status := w_status;
         o_errm := w_errm;
      ELSE
         o_status := 'E';
         o_errm := SQLERRM;
      END IF;
END;
$$;


ALTER FUNCTION public.fn_sales_sales_tran_table_insert(p_branch_code integer, p_center_code character, p_app_user_id character, p_customer_phone character, p_account_number character, p_bill_amount numeric, p_pay_amount numeric, p_discount_amount numeric, p_bill_receive_gl character, p_bill_due_gl character, p_discount_ledger character, p_transaction_type character, p_payment_type character, p_transaction_date date, p_employee_id character, p_document_number character, OUT o_status character, OUT o_errm character) OWNER TO postgres;

--
-- Name: fn_sales_stock_authorization(integer, character, character, character, numeric, numeric, numeric, character, character, date, character, character, character, character); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_sales_stock_authorization(p_branch_code integer, p_app_user_id character, p_supplier_id character, p_account_number character, p_bill_amount numeric, p_pay_amount numeric, p_discount_amount numeric, p_bill_payment_gl character, p_transaction_type character, p_stock_date date, p_stock_id character, p_approve_reject character, p_voucher_number character, p_payment_comments character, OUT o_status character, OUT o_errm character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_error_message             VARCHAR;
   w_batch_serial              INTEGER;
   w_tran_amount               NUMERIC (22, 2) := 0;
   w_total_product_price       NUMERIC (22, 2) := 0;
   w_discount_amount           NUMERIC (22, 2) := 0;
   w_product_current_rate      NUMERIC (22, 2) := 0;
   w_total_product             INTEGER;
   w_product_available_stock   INTEGER;
   w_tran_naration             VARCHAR;
   product_list                RECORD;
   w_tran_gl_code              VARCHAR := '0';
   w_serial_no                 INTEGER := 0;
   w_status                    VARCHAR;
   w_errm                      VARCHAR;
   w_batch_number              INTEGER;
   w_product_id                VARCHAR;
   w_last_balance_update       DATE;
   w_last_transaction_date     DATE;
BEGIN
   IF p_approve_reject = 'A'
   THEN
      SELECT sum (t.total_price), sum (t.quantity), sum (t.discount_amount)
        INTO w_total_product_price, w_total_product, w_discount_amount
        FROM sales_stockdetails t, sales_products p
       WHERE p.product_id = t.product_id AND stock_id = p_stock_id;

      w_discount_amount := p_discount_amount;
      w_total_product_price := p_bill_amount;

      FOR product_list IN (SELECT *
                             FROM sales_stockdetails s
                            WHERE s.stock_id = p_stock_id)
      LOOP
         BEGIN
            SELECT product_id, product_current_rate, product_available_stock
              INTO STRICT w_product_id,
                          w_product_current_rate,
                          w_product_available_stock
              FROM sales_products
             WHERE product_id = product_list.product_id;

            IF w_product_available_stock < 0
            THEN
               RAISE EXCEPTION
               USING MESSAGE = 'Available stock can not be less then zero!';
            END IF;

            BEGIN
               w_product_current_rate :=
                  round (
                     (  (  (  w_product_current_rate
                            * w_product_available_stock)
                         + product_list.total_price)
                      / (w_product_available_stock + product_list.quantity)),
                     2);
            EXCEPTION
               WHEN OTHERS
               THEN
                  w_product_current_rate := w_product_current_rate;
            END;

            UPDATE sales_products
               SET product_total_stock =
                      product_total_stock + product_list.quantity,
                   product_available_stock =
                      product_available_stock + product_list.quantity,
                   total_purchase_amount =
                      total_purchase_amount + product_list.total_price,
                   product_last_stock_date = p_stock_date,
                   product_current_rate = w_product_current_rate
             WHERE product_id = product_list.product_id;
         EXCEPTION
            WHEN NO_DATA_FOUND
            THEN
               RAISE EXCEPTION USING MESSAGE = 'Invalid Product Code!';
         END;

         BEGIN
            SELECT product_id, inv_balance_upto_date, last_stock_date
              INTO STRICT w_product_id,
                          w_last_balance_update,
                          w_last_transaction_date
              FROM sales_products_inventory_status
             WHERE     product_id = product_list.product_id
                   AND branch_code = p_branch_code;

            w_last_balance_update :=
               LEAST (w_last_balance_update, p_stock_date);
            w_last_transaction_date :=
               GREATEST (w_last_transaction_date, p_stock_date);

            UPDATE sales_products_inventory_status
               SET product_total_stock =
                      product_total_stock + product_list.quantity,
                   product_available_stock =
                      product_available_stock + product_list.quantity,
                   total_purchase_amount =
                      total_purchase_amount + product_list.total_price,
                   last_stock_date = w_last_transaction_date,
                   inv_balance_upto_date = w_last_balance_update,
                   is_balance_updated = FALSE
             WHERE     product_id = product_list.product_id
                   AND branch_code = p_branch_code;
         EXCEPTION
            WHEN NO_DATA_FOUND
            THEN
               INSERT INTO sales_products_inventory_status (
                              product_id,
                              product_total_stock,
                              total_order_quantity,
                              product_total_sales,
                              total_stock_return,
                              total_sales_return,
                              product_total_damage,
                              product_available_stock,
                              last_stock_date,
                              last_order_date,
                              last_sale_date,
                              last_stock_return_date,
                              last_sales_return_date,
                              inv_balance_upto_date,
                              total_purchase_amount,
                              product_purchase_rate,
                              total_sales_amount,
                              sales_return_amount,
                              total_damage_amount,
                              damage_receive_amount,
                              cost_of_good_sold,
                              stock_return_amount,
                              total_discount_pay,
                              total_discount_receive,
                              branch_code,
                              is_balance_updated,
                              app_user_id,
                              app_data_time)
                    VALUES (product_list.product_id,
                            product_list.quantity,
                            0,
                            0,
                            0,
                            0,
                            0,
                            product_list.quantity,
                            p_stock_date,
                            NULL,
                            NULL,
                            NULL,
                            NULL,
                            p_stock_date - 1,
                            product_list.total_price,
                            0,
                            0,
                            0,
                            0.00,
                            0.00,
                            0.00,
                            0.00,
                            0.00,
                            0.00,
                            p_branch_code,
                            FALSE,
                            p_app_user_id,
                            current_timestamp);
         END;
      END LOOP;

      BEGIN
         INSERT INTO sales_stockmaster (stock_id,
                                        supplier_id,
                                        stock_date,
                                        voucher_number,
                                        show_room,
                                        status,
                                        tran_type_code,
                                        payment_comments,
                                        total_quantity,
                                        returned_quantity,
                                        returned_amount,
                                        cancel_quantity,
                                        cancel_amount,
                                        total_price,
                                        total_pay,
                                        due_amount,
                                        comments,
                                        branch_code,
                                        app_user_id,
                                        app_data_time)
            SELECT stock_id,
                   p_supplier_id,
                   p_stock_date,
                   p_voucher_number,
                   show_room,
                   'S',
                   p_transaction_type,
                   p_payment_comments,
                   total_quantity,
                   returned_quantity,
                   returned_amount,
                   cancel_quantity,
                   cancel_amount,
                   total_price,
                   p_pay_amount,
                   w_total_product_price - p_pay_amount,
                   comments,
                   p_branch_code,
                   app_user_id,
                   app_data_time
              FROM sales_stockmasterauthq
             WHERE stock_id = p_stock_id;
      END;

      IF p_bill_amount > 0
      THEN
         BEGIN
            SELECT *
              INTO w_status, w_errm, w_batch_number
              FROM fn_sales_stock_tran_table_insert (p_branch_code,
                                                     p_app_user_id,
                                                     p_supplier_id,
                                                     p_account_number,
                                                     w_total_product_price,
                                                     p_pay_amount,
                                                     p_bill_payment_gl,
                                                     'STOCK',
                                                     p_transaction_type,
                                                     p_stock_date,
                                                     p_stock_id);

            IF w_status = 'E'
            THEN
               RAISE EXCEPTION USING MESSAGE = w_errm;
            END IF;
         END;

         BEGIN
            SELECT *
              INTO w_status, w_errm, w_batch_number
              FROM fn_finance_post_tran (p_branch_code,
                                         '0',
                                         p_app_user_id,
                                         p_transaction_type,
                                         p_stock_date,
                                         'Stock Posting',
                                         'STOCK');

            IF w_status = 'E' AND w_batch_number = 0
            THEN
               RAISE EXCEPTION USING MESSAGE = w_errm;
            ELSE
               UPDATE sales_stockmaster
                  SET tran_batch_number = w_batch_number, status = 'S'
                WHERE stock_id = p_stock_id;

               UPDATE sales_stockdetails
                  SET status = 'S', supplier_id = p_supplier_id
                WHERE stock_id = p_stock_id;

               DELETE FROM sales_stockmasterauthq
                     WHERE stock_id = p_stock_id;
            END IF;
         END;
      ELSE
         UPDATE sales_stockmaster
            SET tran_batch_number = w_batch_number, status = 'S'
          WHERE stock_id = p_stock_id;

         UPDATE sales_stockdetails
            SET status = 'S', supplier_id = p_supplier_id
          WHERE stock_id = p_stock_id;

         DELETE FROM sales_stockmasterauthq
               WHERE stock_id = p_stock_id;
      END IF;
   ELSE
      UPDATE sales_stockdetails
         SET status = 'J'
       WHERE stock_id = p_stock_id;

      UPDATE sales_stockmasterauthq
         SET status = 'J'
       WHERE stock_id = p_stock_id;
   END IF;

   o_status := 'S';
   o_errm := '';
EXCEPTION
   WHEN OTHERS
   THEN
      IF w_status = 'E'
      THEN
         o_status := w_status;
         o_errm := w_errm;
      ELSE
         o_status := 'E';
         o_errm := SQLERRM;
      END IF;
END;
$$;


ALTER FUNCTION public.fn_sales_stock_authorization(p_branch_code integer, p_app_user_id character, p_supplier_id character, p_account_number character, p_bill_amount numeric, p_pay_amount numeric, p_discount_amount numeric, p_bill_payment_gl character, p_transaction_type character, p_stock_date date, p_stock_id character, p_approve_reject character, p_voucher_number character, p_payment_comments character, OUT o_status character, OUT o_errm character) OWNER TO postgres;

--
-- Name: fn_sales_stock_cancel(integer, character, character, character); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_sales_stock_cancel(p_branch_code integer, p_app_user_id character, p_stock_id character, p_cancel_reason character, OUT o_status character, OUT o_errm character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_status                  VARCHAR;
   w_errm                    VARCHAR;
   product_list              RECORD;
   product_return_list       RECORD;
   product_return_details    RECORD;
   w_stock_date              DATE;
   w_tran_batch_number       INTEGER;
   w_stock_status            VARCHAR;
   w_last_balance_update     DATE;
   w_last_transaction_date   DATE;
BEGIN
   BEGIN
      SELECT stock_date, tran_batch_number, status
        INTO w_stock_date, w_tran_batch_number, w_stock_status
        FROM sales_stockmaster
       WHERE stock_id = p_stock_id;
   END;

   IF w_stock_status = 'C'
   THEN
      w_status := 'E';
      w_errm := 'Batch already canceled!';
      RAISE EXCEPTION USING MESSAGE = w_errm;
   END IF;


   FOR product_list IN (SELECT *
                          FROM sales_stockdetails s
                         WHERE s.stock_id = p_stock_id)
   LOOP
      w_last_transaction_date := product_list.stock_date;

      SELECT inv_balance_upto_date
       INTO STRICT w_last_balance_update
       FROM sales_products_inventory_status
      WHERE     product_id = product_list.product_id
            AND branch_code = p_branch_code;

      w_last_balance_update :=
         LEAST (w_last_balance_update, w_last_transaction_date);
      w_last_transaction_date :=
         GREATEST (w_last_transaction_date, w_last_transaction_date);

      UPDATE sales_products_inventory_status
         SET product_total_stock =
                  product_total_stock
                - (product_list.quantity - product_list.returned_quantity),
             product_available_stock =
                  product_available_stock
                - (product_list.quantity - product_list.returned_quantity),
             total_purchase_amount =
                total_purchase_amount - product_list.total_price,
             inv_balance_upto_date = w_last_balance_update,
             is_balance_updated = FALSE
       WHERE     product_id = product_list.product_id
             AND branch_code = p_branch_code;

      UPDATE sales_products
         SET product_total_stock =
                  product_total_stock
                - (product_list.quantity - product_list.returned_quantity),
             product_available_stock =
                  product_available_stock
                - (product_list.quantity - product_list.returned_quantity),
             total_purchase_amount =
                total_purchase_amount - product_list.total_price
       WHERE product_id = product_list.product_id;

      UPDATE sales_stockdetails
         SET STATUS = 'C'
       WHERE     stock_id = p_stock_id
             AND branch_code = p_branch_code
             AND product_id = product_list.product_id;
   END LOOP;

   BEGIN
      FOR product_return_list IN (SELECT DISTINCT stock_id,
                                                  return_date,
                                                  tran_batch_number,
                                                  branch_code
                                    FROM sales_stock_return_details
                                   WHERE stock_id = p_stock_id)
      LOOP
         SELECT *
         INTO w_status, w_errm
         FROM fn_finance_post_tran_cancel (
                 product_return_list.branch_code,
                 p_app_user_id,
                 product_return_list.return_date,
                 product_return_list.tran_batch_number,
                 p_cancel_reason);

         IF w_status = 'E'
         THEN
            RAISE EXCEPTION USING MESSAGE = w_errm;
         ELSE
            FOR product_return_details IN (SELECT product_id,
                                                  returned_quantity,
                                                  return_amount,
                                                  branch_code
                                             FROM sales_stock_return_details
                                            WHERE stock_id = p_stock_id)
            LOOP
               UPDATE sales_products_inventory_status
                  SET product_available_stock =
                           product_available_stock
                         - (product_return_details.returned_quantity),
                      total_stock_return =
                           total_stock_return
                         + (product_return_details.returned_quantity),
                      last_stock_return_date = current_date,
                      total_stock_return_amount =
                           total_stock_return_amount
                         + product_return_details.return_amount
                WHERE     product_id = product_return_details.product_id
                      AND branch_code = product_return_details.branch_code;

               UPDATE sales_products
                  SET total_stock_return =
                           total_stock_return
                         - product_return_details.returned_quantity,
                      total_stock_return_amount =
                           total_stock_return_amount
                         - product_return_details.return_amount
                WHERE product_id = product_return_details.product_id;

               UPDATE sales_stock_return_details
                  SET status = 'C'
                WHERE     product_id = product_return_details.product_id
                      AND stock_id = p_stock_id
                      AND branch_code = p_branch_code;
            END LOOP;
         END IF;
      END LOOP;
   END;

   BEGIN
      SELECT *
        INTO w_status, w_errm
        FROM fn_finance_post_tran_cancel (p_branch_code,
                                          p_app_user_id,
                                          w_stock_date,
                                          w_tran_batch_number,
                                          p_cancel_reason);

      IF w_status = 'E'
      THEN
         RAISE EXCEPTION USING MESSAGE = w_errm;
      ELSE
         BEGIN
            UPDATE sales_stockmaster
               SET STATUS = 'C'
             WHERE stock_id = p_stock_id;
         END;
      END IF;
   END;

   o_status := 'S';
   o_errm := '';
EXCEPTION
   WHEN OTHERS
   THEN
      IF w_status = 'E'
      THEN
         o_status := w_status;
         o_errm := w_errm;
      ELSE
         o_status := 'E';
         o_errm := SQLERRM;
      END IF;
END;
$$;


ALTER FUNCTION public.fn_sales_stock_cancel(p_branch_code integer, p_app_user_id character, p_stock_id character, p_cancel_reason character, OUT o_status character, OUT o_errm character) OWNER TO postgres;

--
-- Name: fn_sales_stock_return(integer, character, character, date, character, integer, character, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_sales_stock_return(p_branch_code integer, p_app_user_id character, p_stock_id character, p_stock_date date, p_product_id character, p_returned_quantity integer, p_return_reason character, p_return_date date, OUT o_status character, OUT o_errm character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_status                  VARCHAR;
   w_errm                    VARCHAR;
   product_list              RECORD;
   w_stock_date              DATE;
   w_tran_batch_number       INTEGER;
   w_stock_status            VARCHAR;
   w_supplier_phone          VARCHAR;
   w_tran_gl_code            VARCHAR := '0';
   w_account_ledger_code     VARCHAR := '0';
   w_contra_gl_code          VARCHAR := '0';
   w_serial_no               INTEGER := 0;
   w_tran_amount             NUMERIC (22, 2) := 0;
   w_tran_naration           VARCHAR;
   w_debit_credit            VARCHAR;
   w_total_return_amount     NUMERIC (22, 2) := 0;
   w_account_number          VARCHAR := 0;
   w_supplier_account        VARCHAR := '0';
   w_return_voucher          VARCHAR;
   w_stock_voucher_number    VARCHAR;
   w_batch_number            INTEGER;
   w_sql_statements          VARCHAR;
   w_supplier_id             VARCHAR;
   w_last_balance_update     DATE;
   w_last_transaction_date   DATE;

   cur_all_products CURSOR FOR
      SELECT s.quantity,
             s.quantity * s.purces_price total_price,
             s.purces_price,
             s.product_id,
             s.branch_code,
             p.product_stock_gl,
             s.returned_quantity
        FROM sales_stockdetails s, sales_products p
       WHERE     p.product_id = s.product_id
             AND s.branch_code = p_branch_code
             AND s.app_user_id = p_app_user_id
             AND s.stock_id = p_stock_id;

   cur_products CURSOR FOR
      SELECT p_returned_quantity quantity,
             p_returned_quantity * s.purces_price total_price,
             s.purces_price,
             s.product_id,
             s.branch_code,
             p.product_stock_gl,
             s.returned_quantity
        FROM sales_stockdetails s, sales_products p
       WHERE     p.product_id = s.product_id
             AND s.branch_code = p_branch_code
             AND s.app_user_id = p_app_user_id
             AND s.stock_id = p_stock_id
             AND s.product_id = p_product_id;
BEGIN
   BEGIN
      SELECT supplier_id,
             stock_date,
             tran_batch_number,
             status,
             voucher_number
        INTO w_supplier_id,
             w_stock_date,
             w_tran_batch_number,
             w_stock_status,
             w_stock_voucher_number
        FROM sales_stockmaster
       WHERE stock_id = p_stock_id AND branch_code = p_branch_code;
   END;

   IF w_stock_status = 'R'
   THEN
      RAISE EXCEPTION USING MESSAGE = 'Transaction already returned!';
   END IF;

   w_return_voucher :=
      fn_get_inventory_number (30016,
                               1,
                               'RT',
                               'Stock Return Voucher Number',
                               8);

   BEGIN
      SELECT DISTINCT account_number
        INTO w_supplier_account
        FROM finance_transaction_details
       WHERE     batch_number = w_tran_batch_number
             AND transaction_date = w_stock_date
             AND branch_code = p_branch_code
             AND account_number <> '0';
   EXCEPTION
      WHEN OTHERS
      THEN
         w_status := 'E';
         w_errm := SQLERRM;
         RAISE EXCEPTION USING MESSAGE = w_errm;
   END;

   BEGIN
      SELECT account_ledger_code
        INTO STRICT w_account_ledger_code
        FROM finance_accounts_balance
       WHERE account_number = w_supplier_account;
   EXCEPTION
      WHEN NO_DATA_FOUND
      THEN
         RAISE EXCEPTION
         USING MESSAGE =
                  'Invalid Account Number ' || w_supplier_account || '!';
   END;

   IF w_stock_status = 'C'
   THEN
      w_status := 'E';
      w_errm := 'You can not return the canceled batch!';
      RAISE EXCEPTION USING MESSAGE = w_errm;
   END IF;


   IF p_product_id != 'ALL'
   THEN
      OPEN cur_products;
   ELSE
      OPEN cur_all_products;
   END IF;

   LOOP
      IF p_product_id != 'ALL'
      THEN
         FETCH cur_products INTO product_list;
      ELSE
         FETCH cur_all_products INTO product_list;
      END IF;

      EXIT WHEN NOT FOUND;


      --w_tran_gl_code := product_list.product_stock_gl;
      w_tran_amount := product_list.total_price;
      w_total_return_amount :=
         w_total_return_amount + product_list.total_price;
      w_tran_naration := 'Stock Return for ' || p_stock_id;
      w_serial_no := w_serial_no + 1;
      w_debit_credit := 'C';
      w_account_number := w_supplier_account;
      w_tran_gl_code := '0';
      w_contra_gl_code := product_list.product_stock_gl;

      INSERT INTO finance_transaction_table (branch_code,
                                             center_code,
                                             transaction_date,
                                             batch_serial,
                                             account_number,
                                             tran_gl_code,
                                             contra_gl_code,
                                             tran_debit_credit,
                                             tran_type,
                                             tran_amount,
                                             available_balance,
                                             tran_person_phone,
                                             tran_person_name,
                                             tran_document_prefix,
                                             tran_document_number,
                                             tran_sign_verified,
                                             system_posted_tran,
                                             transaction_narration,
                                             app_user_id,
                                             app_data_time)
           VALUES (p_branch_code,
                   '0',
                   p_return_date,
                   w_serial_no,
                   w_account_number,
                   w_tran_gl_code,
                   w_contra_gl_code,
                   w_debit_credit,
                   'STOCK_RETURN',
                   w_tran_amount,
                   0,
                   w_supplier_phone,
                   '',
                   NULL,
                   p_stock_id,
                   FALSE,
                   TRUE,
                   w_tran_naration,
                   p_app_user_id,
                   current_timestamp);

      BEGIN
         w_debit_credit := 'D';
         w_tran_amount := w_total_return_amount;
         w_tran_naration := 'Stock Return for ' || p_stock_id;
         w_serial_no = w_serial_no + 1;
         w_contra_gl_code := w_account_ledger_code;
         w_account_number := '0';
         w_tran_gl_code := product_list.product_stock_gl;

         INSERT INTO finance_transaction_table (branch_code,
                                                center_code,
                                                transaction_date,
                                                batch_serial,
                                                account_number,
                                                tran_gl_code,
                                                contra_gl_code,
                                                tran_debit_credit,
                                                tran_type,
                                                tran_amount,
                                                available_balance,
                                                tran_person_phone,
                                                tran_person_name,
                                                tran_document_prefix,
                                                tran_document_number,
                                                tran_sign_verified,
                                                system_posted_tran,
                                                transaction_narration,
                                                app_user_id,
                                                app_data_time)
              VALUES (p_branch_code,
                      '0',
                      p_return_date,
                      w_serial_no,
                      w_account_number,
                      w_tran_gl_code,
                      w_contra_gl_code,
                      w_debit_credit,
                      'STOCK_RETURN',
                      w_tran_amount,
                      0.00,
                      w_supplier_phone,
                      NULL,
                      NULL,
                      p_stock_id,
                      FALSE,
                      TRUE,
                      w_tran_naration,
                      p_app_user_id,
                      current_timestamp);
      END;

      INSERT INTO sales_stock_return_details (supplier_id,
                                              stock_id,
                                              stock_voucher,
                                              product_id,
                                              tran_type_code,
                                              tran_batch_number,
                                              returned_quantity,
                                              return_amount,
                                              return_voucher,
                                              return_reason,
                                              branch_code,
                                              app_user_id,
                                              app_data_time,
                                              stock_date,
                                              return_date)
           VALUES (w_supplier_id,
                   p_stock_id,
                   w_stock_voucher_number,
                   product_list.product_id,
                   NULL,
                   NULL,
                   product_list.quantity,
                   product_list.total_price,
                   w_return_voucher,
                   p_return_reason,
                   product_list.branch_code,
                   p_app_user_id,
                   current_timestamp,
                   w_stock_date,
                   p_return_date);

      SELECT inv_balance_upto_date,
             COALESCE (last_stock_date, p_return_date) product_last_stock_date
        INTO STRICT w_last_balance_update, w_last_transaction_date
        FROM sales_products_inventory_status
       WHERE     product_id = product_list.product_id
             AND branch_code = p_branch_code;

      w_last_balance_update := LEAST (w_last_balance_update, p_return_date);
      w_last_transaction_date :=
         GREATEST (w_last_transaction_date, p_return_date);


      UPDATE sales_products_inventory_status
         SET product_available_stock =
                product_available_stock - (product_list.quantity),
             total_purchase_amount =
                total_purchase_amount - product_list.total_price,
             total_stock_return =
                total_stock_return + (product_list.quantity),
             last_stock_return_date = w_last_transaction_date,
             inv_balance_upto_date = w_last_balance_update,
             stock_return_amount =
                stock_return_amount + product_list.total_price,
             is_balance_updated = FALSE
       WHERE     product_id = product_list.product_id
             AND branch_code = p_branch_code;

      UPDATE sales_products
         SET product_available_stock =
                  product_available_stock
                - (product_list.quantity - product_list.quantity),
             total_purchase_amount =
                total_purchase_amount - product_list.total_price,
             total_stock_return =
                  total_stock_return
                + (product_list.quantity - product_list.quantity),
             product_last_return_date = w_last_transaction_date,
             stock_return_amount =
                stock_return_amount + product_list.total_price
       WHERE product_id = product_list.product_id;

      UPDATE sales_stockdetails
         SET returned_quantity =
                  returned_quantity
                + (product_list.quantity - product_list.returned_quantity),
             return_date = p_return_date,
             STATUS =
                (CASE
                    WHEN quantity = product_list.quantity THEN 'R'
                    ELSE 'P'
                 END)
       WHERE     stock_id = p_stock_id
             AND branch_code = p_branch_code
             AND product_id = product_list.product_id;

      BEGIN
         UPDATE sales_stockmaster
            SET STATUS = 'P',
                returned_quantity =
                     returned_quantity
                   + (product_list.quantity - product_list.returned_quantity),
                returned_amount = returned_amount + product_list.total_price
          WHERE stock_id = p_stock_id AND branch_code = p_branch_code;
      END;
   END LOOP;

   BEGIN
      SELECT *
        INTO w_status, w_errm, w_batch_number
        FROM fn_finance_post_tran (p_branch_code,
                                   '0',
                                   p_app_user_id,
                                   'STOCK_RETURN',
                                   p_return_date,
                                   p_return_reason,
                                   'STOCK_RETURN');

      IF w_status = 'E'
      THEN
         RAISE EXCEPTION USING MESSAGE = w_errm;
      ELSE
         BEGIN
            UPDATE sales_stockmaster
               SET STATUS =
                      (CASE
                          WHEN total_quantity = returned_quantity THEN 'R'
                          ELSE 'P'
                       END)
             WHERE stock_id = p_stock_id AND branch_code = p_branch_code;
         END;

         BEGIN
            UPDATE sales_stock_return_details
               SET tran_batch_number = w_batch_number
             WHERE     return_voucher = w_return_voucher
                   AND branch_code = p_branch_code;
         END;
      END IF;
   END;

   o_status := 'S';
   o_errm := '';
EXCEPTION
   WHEN OTHERS
   THEN
      IF w_status = 'E'
      THEN
         o_status := w_status;
         o_errm := w_errm;
      ELSE
         o_status := 'E';
         o_errm := SQLERRM;
      END IF;
END;
$$;


ALTER FUNCTION public.fn_sales_stock_return(p_branch_code integer, p_app_user_id character, p_stock_id character, p_stock_date date, p_product_id character, p_returned_quantity integer, p_return_reason character, p_return_date date, OUT o_status character, OUT o_errm character) OWNER TO postgres;

--
-- Name: fn_sales_stock_return_by_product(integer, character, character, character, character, integer, numeric, character, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_sales_stock_return_by_product(p_branch_code integer, p_app_user_id character, p_supplier_id character, p_account_number character, p_product_id character, p_returned_quantity integer, p_returned_price numeric, p_return_reason character, p_return_date date, OUT o_status character, OUT o_errm character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_status                  VARCHAR;
   w_errm                    VARCHAR;
   product_list              RECORD;
   w_stock_date              DATE;
   w_tran_batch_number       INTEGER;
   w_stock_status            VARCHAR;
   w_supplier_phone          VARCHAR;
   w_tran_gl_code            VARCHAR := '0';
   w_account_ledger_code     VARCHAR := '0';
   w_contra_gl_code          VARCHAR := '0';
   w_serial_no               INTEGER := 0;
   w_tran_amount             NUMERIC (22, 2) := 0;
   w_tran_narration          VARCHAR;
   w_debit_credit            VARCHAR;
   w_total_return_amount     NUMERIC (22, 2) := 0;
   w_account_number          VARCHAR := '0';
   w_supplier_account        VARCHAR := '0';
   w_return_voucher          VARCHAR;
   w_stock_voucher_number    VARCHAR;
   w_batch_number            INTEGER;
   w_sql_statements          VARCHAR;
   w_parent_delar            INTEGER;
   w_customer_phone          VARCHAR := '';
   w_last_balance_update     DATE;
   w_last_transaction_date   DATE;
BEGIN
   BEGIN
      SELECT account_number, account_ledger_code
        INTO STRICT w_supplier_account, w_account_ledger_code
        FROM finance_accounts_balance
       WHERE account_number = p_account_number;
   EXCEPTION
      WHEN NO_DATA_FOUND
      THEN
         RAISE EXCEPTION
         USING MESSAGE = 'Invalid Supplier ID' || p_supplier_id || '!';
   END;

   w_return_voucher :=
      fn_get_inventory_number (30016,
                               1,
                               'RT',
                               'Stock Return Voucher Number',
                               8);

   FOR product_list IN (SELECT product_id,
                               product_name,
                               product_model,
                               p_returned_quantity quantity,
                               p_returned_price total_price,
                               p.product_stock_gl,
                               p.product_stock_ret_gl,
                               p.product_profit_gl,
                               p.product_loss_gl
                          FROM sales_products p
                         WHERE product_id = p_product_id)
   LOOP
      w_tran_gl_code := product_list.product_stock_gl;
      w_tran_amount := product_list.total_price;
      w_tran_narration :=
            'Stock Return for '
         || product_list.product_name
         || ' '
         || product_list.product_model;
      w_serial_no := w_serial_no + 1;
      w_debit_credit := 'C';
      w_contra_gl_code := w_account_ledger_code;
      w_account_number := '0';

      IF w_tran_amount > 0
      THEN
         INSERT INTO finance_transaction_table (branch_code,
                                                center_code,
                                                transaction_date,
                                                batch_serial,
                                                account_number,
                                                tran_gl_code,
                                                contra_gl_code,
                                                tran_debit_credit,
                                                tran_type,
                                                tran_amount,
                                                available_balance,
                                                tran_person_phone,
                                                tran_person_name,
                                                tran_document_prefix,
                                                tran_document_number,
                                                tran_sign_verified,
                                                system_posted_tran,
                                                transaction_narration,
                                                app_user_id,
                                                app_data_time)
              VALUES (p_branch_code,
                      '0',
                      p_return_date,
                      w_serial_no,
                      w_account_number,
                      w_tran_gl_code,
                      w_contra_gl_code,
                      w_debit_credit,
                      'STOCK_RETURN',
                      w_tran_amount,
                      0,
                      w_customer_phone,
                      '',
                      NULL,
                      w_return_voucher,
                      FALSE,
                      TRUE,
                      w_tran_narration,
                      p_app_user_id,
                      current_timestamp);

         w_serial_no := w_serial_no + 1;
         w_debit_credit := 'D';
         w_account_number := w_supplier_account;
         w_tran_gl_code := '0';
         w_contra_gl_code := product_list.product_stock_gl;

         INSERT INTO finance_transaction_table (branch_code,
                                                center_code,
                                                transaction_date,
                                                batch_serial,
                                                account_number,
                                                tran_gl_code,
                                                contra_gl_code,
                                                tran_debit_credit,
                                                tran_type,
                                                tran_amount,
                                                available_balance,
                                                tran_person_phone,
                                                tran_person_name,
                                                tran_document_prefix,
                                                tran_document_number,
                                                tran_sign_verified,
                                                system_posted_tran,
                                                transaction_narration,
                                                app_user_id,
                                                app_data_time)
              VALUES (p_branch_code,
                      '0',
                      p_return_date,
                      w_serial_no,
                      w_account_number,
                      w_tran_gl_code,
                      w_contra_gl_code,
                      w_debit_credit,
                      'STOCK_RETURN',
                      w_tran_amount,
                      0,
                      w_customer_phone,
                      '',
                      NULL,
                      w_return_voucher,
                      FALSE,
                      TRUE,
                      w_tran_narration,
                      p_app_user_id,
                      current_timestamp);
      END IF;

      INSERT INTO sales_stock_return_details (stock_id,
                                              supplier_id,
                                              stock_voucher,
                                              product_id,
                                              tran_type_code,
                                              tran_batch_number,
                                              returned_quantity,
                                              return_amount,
                                              return_voucher,
                                              return_reason,
                                              branch_code,
                                              app_user_id,
                                              app_data_time,
                                              stock_date,
                                              return_date)
           VALUES ('',
                   p_supplier_id,
                   w_stock_voucher_number,
                   product_list.product_id,
                   NULL,
                   NULL,
                   product_list.quantity,
                   product_list.total_price,
                   w_return_voucher,
                   p_return_reason,
                   p_branch_code,
                   p_app_user_id,
                   current_timestamp,
                   w_stock_date,
                   p_return_date);

      SELECT inv_balance_upto_date,
             COALESCE (last_stock_return_date, p_return_date) last_stock_return_date
        INTO STRICT w_last_balance_update, w_last_transaction_date
        FROM sales_products_inventory_status
       WHERE     product_id = product_list.product_id
             AND branch_code = p_branch_code;

      w_last_balance_update := LEAST (w_last_balance_update, p_return_date);
      w_last_transaction_date :=
         GREATEST (w_last_transaction_date, p_return_date);

      UPDATE sales_products_inventory_status
         SET product_available_stock =
                product_available_stock - (product_list.quantity),
             total_purchase_amount =
                total_purchase_amount - product_list.total_price,
             total_stock_return =
                total_stock_return + (product_list.quantity),
             last_stock_return_date = w_last_transaction_date,
             inv_balance_upto_date = w_last_balance_update,
             stock_return_amount =
                stock_return_amount + product_list.total_price,
             is_balance_updated = FALSE
       WHERE     product_id = product_list.product_id
             AND branch_code = p_branch_code;

      UPDATE sales_products
         SET product_available_stock =
                  product_available_stock
                - (product_list.quantity - product_list.quantity),
             total_purchase_amount =
                total_purchase_amount - product_list.total_price,
             total_stock_return =
                  total_stock_return
                + (product_list.quantity - product_list.quantity),
             product_last_return_date = w_last_transaction_date,
             stock_return_amount =
                stock_return_amount + product_list.total_price
       WHERE product_id = product_list.product_id;
   END LOOP;

   BEGIN
      SELECT *
        INTO w_status, w_errm, w_batch_number
        FROM fn_finance_post_tran (p_branch_code,
                                   '0',
                                   p_app_user_id,
                                   'STOCK_RETURN',
                                   p_return_date,
                                   p_return_reason,
                                   'STOCK_RETURN');

      IF w_status = 'E'
      THEN
         RAISE EXCEPTION USING MESSAGE = w_errm;
      ELSE
         BEGIN
            UPDATE sales_stock_return_details
               SET tran_batch_number = w_batch_number
             WHERE     return_voucher = w_return_voucher
                   AND branch_code = p_branch_code;
         END;
      END IF;
   END;

   o_status := 'S';
   o_errm := '';
EXCEPTION
   WHEN OTHERS
   THEN
      IF w_status = 'E'
      THEN
         o_status := w_status;
         o_errm := w_errm;
      ELSE
         o_status := 'E';
         o_errm := SQLERRM;
      END IF;
END;
$$;


ALTER FUNCTION public.fn_sales_stock_return_by_product(p_branch_code integer, p_app_user_id character, p_supplier_id character, p_account_number character, p_product_id character, p_returned_quantity integer, p_returned_price numeric, p_return_reason character, p_return_date date, OUT o_status character, OUT o_errm character) OWNER TO postgres;

--
-- Name: fn_sales_stock_submit(date, integer, character, integer, integer, character, character); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_sales_stock_submit(p_stock_date date, p_branch_code integer, p_app_user_id character, p_supplier_id integer, p_show_room_id integer, p_voucher_number character, p_comments character, OUT o_status character, OUT o_errm character, OUT o_stock_id character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_message               VARCHAR;
   w_stock_id              VARCHAR;
   w_total_product_price   NUMERIC (22, 2);
   w_total_product         NUMERIC (22, 2);
   w_discount_amount       NUMERIC (22, 2);
   w_voucher_number        VARCHAR;
   w_status                VARCHAR;
   w_errm                  VARCHAR;
BEGIN
   w_stock_id :=
      fn_get_inventory_number (30015,
                               100,
                               'ST',
                               'Stock Voucher Number',
                               8);

   INSERT INTO sales_stockdetails (stock_id,
                                   supplier_id,
                                   product_id,
                                   purces_price,
                                   total_price,
                                   discount_amount,
                                   status,
                                   quantity,
                                   returned_quantity,
                                   return_date,
                                   stock_date,
                                   comments,
                                   app_user_id,
                                   app_data_time,
                                   branch_code)
      SELECT w_stock_id,
             p_supplier_id,
             t.product_id,
             t.purces_price,
             t.total_price,
             t.discount_amount,
             'W' status,
             t.quantity,
             0  returned_quantity,
             NULL return_date,
             p_stock_date stock_date,
             t.comments,
             t.app_user_id,
             t.app_data_time,
             p_branch_code
        FROM sales_stockdetailstemp t, sales_products p
       WHERE p.product_id = t.product_id AND t.app_user_id = p_app_user_id;

   SELECT sum (t.total_price), sum (t.quantity), sum (t.discount_amount)
     INTO w_total_product_price, w_total_product, w_discount_amount
     FROM sales_stockdetailstemp t, sales_products p
    WHERE p.product_id = t.product_id AND t.app_user_id = p_app_user_id;

   INSERT INTO sales_stockmasterauthq (stock_id,
                                       supplier_id,
                                       stock_date,
                                       voucher_number,
                                       show_room,
                                       status,
                                       tran_type_code,
                                       payment_comments,
                                       total_quantity,
                                       returned_quantity,
                                       returned_amount,
                                       cancel_quantity,
                                       cancel_amount,
                                       total_price,
                                       discount_amount,
                                       total_pay,
                                       due_amount,
                                       comments,
                                       branch_code,
                                       app_user_id,
                                       app_data_time)
        VALUES (w_stock_id,
                p_supplier_id,
                p_stock_date,
                p_voucher_number,
                p_show_room_id,
                'W',
                'CS',
                NULL,
                w_total_product,
                0,
                0,
                0,
                0,
                w_total_product_price,
                w_discount_amount,
                0,
                w_total_product_price,
                p_comments,
                p_branch_code,
                p_app_user_id,
                current_timestamp);

   DELETE FROM sales_stockdetailstemp
         WHERE app_user_id = p_app_user_id;

   o_stock_id := w_stock_id;
   o_status := 'S';
   o_errm := '';
EXCEPTION
   WHEN OTHERS
   THEN
      IF w_status = 'E'
      THEN
         o_status := w_status;
         o_errm := w_errm;
      ELSE
         o_status := 'E';
         o_errm := SQLERRM;
      END IF;
END;
$$;


ALTER FUNCTION public.fn_sales_stock_submit(p_stock_date date, p_branch_code integer, p_app_user_id character, p_supplier_id integer, p_show_room_id integer, p_voucher_number character, p_comments character, OUT o_status character, OUT o_errm character, OUT o_stock_id character) OWNER TO postgres;

--
-- Name: fn_sales_stock_tran_table_insert(integer, character, character, character, numeric, numeric, character, character, character, date, character); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_sales_stock_tran_table_insert(p_branch_code integer, p_app_user_id character, p_customer_phone character, p_account_number character, p_bill_amount numeric, p_pay_amount numeric, p_bill_payment_gl character, p_transaction_type character, p_payment_type character, p_transaction_date date, p_document_number character, OUT o_status character, OUT o_errm character) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
   w_error_message         VARCHAR;
   w_debit_credit          VARCHAR;
   w_batch_serial          INTEGER;
   w_tran_amount           NUMERIC (22, 2) := 0;
   w_total_debit_amount    NUMERIC (22, 2) := 0;
   w_total_credit_amount   NUMERIC (22, 2) := 0;
   w_total_order_amount    NUMERIC (22, 2) := 0;
   w_tran_naration         VARCHAR;
   tran_list               RECORD;
   w_tran_gl_code          VARCHAR := '0';
   w_contra_gl_code        VARCHAR := '0';
   w_serial_no             INTEGER := 0;
   w_status                VARCHAR;
   w_errm                  VARCHAR;
BEGIN
   IF p_transaction_type IN ('STOCK', 'ORDER')
   THEN
      w_debit_credit := 'D';
   ELSE
      w_debit_credit := 'C';
   END IF;

   FOR tran_list
      IN (SELECT *
          FROM (  SELECT sum (tran_amount) tran_amount,
                         tran_gl_code,
                         tran_naration
                    FROM (  SELECT (s.total_price - s.discount_amount)
                                      tran_amount,
                                   (CASE
                                       WHEN p_transaction_type = 'STOCK'
                                       THEN
                                          product_stock_gl
                                       WHEN p_transaction_type = 'SALES'
                                       THEN
                                          product_sales_gl
                                       WHEN p_transaction_type = 'ORDER'
                                       THEN
                                          product_order_gl
                                       WHEN p_transaction_type = 'PROFIT'
                                       THEN
                                          product_profit_gl
                                       WHEN p_transaction_type = 'LOSS'
                                       THEN
                                          product_loss_gl
                                    END)
                                      tran_gl_code,
                                   substr (
                                         initcap (p_transaction_type)
                                      || ' for '
                                      || initcap (p.product_name),
                                      0,
                                      100)
                                      tran_naration
                              FROM sales_stockdetails s, sales_products p
                             WHERE     p.product_id = s.product_id
                                   AND s.stock_id = p_document_number
                          ORDER BY s.id) o
                GROUP BY tran_gl_code, tran_naration) s)
   LOOP
      w_tran_gl_code := tran_list.tran_gl_code;
      w_tran_amount := tran_list.tran_amount;
      w_tran_naration := tran_list.tran_naration;
      w_serial_no := w_serial_no + 1;

      IF w_tran_amount > 0
      THEN
         INSERT INTO finance_transaction_table (branch_code,
                                                center_code,
                                                transaction_date,
                                                batch_serial,
                                                account_number,
                                                tran_gl_code,
                                                contra_gl_code,
                                                tran_debit_credit,
                                                tran_type,
                                                tran_amount,
                                                available_balance,
                                                tran_person_phone,
                                                tran_person_name,
                                                tran_document_prefix,
                                                tran_document_number,
                                                tran_sign_verified,
                                                system_posted_tran,
                                                transaction_narration,
                                                app_user_id,
                                                app_data_time)
              VALUES (p_branch_code,
                      '0',
                      p_transaction_date,
                      w_serial_no,
                      '0',
                      w_tran_gl_code,
                      w_contra_gl_code,
                      w_debit_credit,
                      p_payment_type,
                      w_tran_amount,
                      0,
                      p_customer_phone,
                      p_app_user_id,
                      NULL,
                      p_document_number,
                      FALSE,
                      TRUE,
                      w_tran_naration,
                      p_app_user_id,
                      current_timestamp);
      END IF;
   END LOOP;

   SELECT parent_code
     INTO w_contra_gl_code
     FROM finance_general_ledger
    WHERE reporting_gl_code = w_tran_gl_code;

   IF p_bill_amount > 0
   THEN
      BEGIN
         w_debit_credit := 'C';
         w_tran_amount := p_bill_amount;
         w_tran_naration := 'Purchase bill for ' || p_document_number;
         w_serial_no := w_serial_no + 1;

         INSERT INTO finance_transaction_table (branch_code,
                                                center_code,
                                                transaction_date,
                                                batch_serial,
                                                account_number,
                                                tran_gl_code,
                                                contra_gl_code,
                                                tran_debit_credit,
                                                tran_type,
                                                tran_amount,
                                                available_balance,
                                                tran_person_phone,
                                                tran_person_name,
                                                tran_document_prefix,
                                                tran_document_number,
                                                tran_sign_verified,
                                                system_posted_tran,
                                                transaction_narration,
                                                app_user_id,
                                                app_data_time)
              VALUES (p_branch_code,
                      '0',
                      p_transaction_date,
                      w_serial_no,
                      p_account_number,
                      '0',
                      w_contra_gl_code,
                      w_debit_credit,
                      p_payment_type,
                      w_tran_amount,
                      0.00,
                      p_customer_phone,
                      NULL,
                      NULL,
                      p_document_number,
                      FALSE,
                      TRUE,
                      w_tran_naration,
                      p_app_user_id,
                      current_timestamp);
      END;
   END IF;


   IF p_pay_amount > 0 AND p_bill_amount > 0
   THEN
      BEGIN
         w_debit_credit := 'C';
         w_tran_amount := p_pay_amount;
         w_tran_naration := 'Purchase payment for ' || p_document_number;
         w_serial_no := w_serial_no + 1;
         w_tran_gl_code := p_bill_payment_gl;

         INSERT INTO finance_transaction_table (branch_code,
                                                center_code,
                                                transaction_date,
                                                batch_serial,
                                                account_number,
                                                tran_gl_code,
                                                contra_gl_code,
                                                tran_debit_credit,
                                                tran_type,
                                                tran_amount,
                                                available_balance,
                                                tran_person_phone,
                                                tran_person_name,
                                                tran_document_prefix,
                                                tran_document_number,
                                                tran_sign_verified,
                                                system_posted_tran,
                                                transaction_narration,
                                                app_user_id,
                                                app_data_time)
              VALUES (p_branch_code,
                      '0',
                      p_transaction_date,
                      w_serial_no,
                      '0',
                      w_tran_gl_code,
                      w_contra_gl_code,
                      w_debit_credit,
                      p_payment_type,
                      w_tran_amount,
                      0.00,
                      p_customer_phone,
                      NULL,
                      NULL,
                      p_document_number,
                      FALSE,
                      TRUE,
                      w_tran_naration,
                      p_app_user_id,
                      current_timestamp);
      END;
   END IF;


   IF p_pay_amount > 0 AND p_bill_amount > 0
   THEN
      BEGIN
         w_debit_credit := 'D';
         w_tran_amount := p_pay_amount;
         w_tran_naration := 'Purchase Payment for ' || p_document_number;
         w_serial_no = w_serial_no + 1;

         INSERT INTO finance_transaction_table (branch_code,
                                                center_code,
                                                transaction_date,
                                                batch_serial,
                                                account_number,
                                                tran_gl_code,
                                                contra_gl_code,
                                                tran_debit_credit,
                                                tran_type,
                                                tran_amount,
                                                available_balance,
                                                tran_person_phone,
                                                tran_person_name,
                                                tran_document_prefix,
                                                tran_document_number,
                                                tran_sign_verified,
                                                system_posted_tran,
                                                transaction_narration,
                                                app_user_id,
                                                app_data_time)
              VALUES (p_branch_code,
                      '0',
                      p_transaction_date,
                      w_serial_no,
                      p_account_number,
                      '0',
                      w_contra_gl_code,
                      w_debit_credit,
                      p_payment_type,
                      w_tran_amount,
                      0.00,
                      p_customer_phone,
                      NULL,
                      NULL,
                      p_document_number,
                      FALSE,
                      TRUE,
                      w_tran_naration,
                      p_app_user_id,
                      current_timestamp);
      END;
   END IF;

   o_status := 'S';
   o_errm := '';
EXCEPTION
   WHEN OTHERS
   THEN
      IF w_status = 'E'
      THEN
         o_status := w_status;
         o_errm := w_errm;
      ELSE
         o_status := 'E';
         o_errm := SQLERRM;
      END IF;
END;
$$;


ALTER FUNCTION public.fn_sales_stock_tran_table_insert(p_branch_code integer, p_app_user_id character, p_customer_phone character, p_account_number character, p_bill_amount numeric, p_pay_amount numeric, p_bill_payment_gl character, p_transaction_type character, p_payment_type character, p_transaction_date date, p_document_number character, OUT o_status character, OUT o_errm character) OWNER TO postgres;

--
-- Name: gn_get_number_to_pct(numeric, numeric); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.gn_get_number_to_pct(p_obtain_marks numeric, p_total_marks numeric) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
   RETURN round ((p_obtain_marks / p_total_marks) * 100, 2);
END;
$$;


ALTER FUNCTION public.gn_get_number_to_pct(p_obtain_marks numeric, p_total_marks numeric) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: auth_group; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.auth_group (
    id integer NOT NULL,
    name character varying(150) NOT NULL
);


ALTER TABLE public.auth_group OWNER TO postgres;

--
-- Name: auth_group_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.auth_group ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.auth_group_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: auth_group_permissions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.auth_group_permissions (
    id integer NOT NULL,
    group_id integer NOT NULL,
    permission_id integer NOT NULL
);


ALTER TABLE public.auth_group_permissions OWNER TO postgres;

--
-- Name: auth_group_permissions_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.auth_group_permissions ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.auth_group_permissions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: auth_permission; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.auth_permission (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    content_type_id integer NOT NULL,
    codename character varying(100) NOT NULL
);


ALTER TABLE public.auth_permission OWNER TO postgres;

--
-- Name: auth_permission_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.auth_permission ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.auth_permission_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: auth_user; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.auth_user (
    id integer NOT NULL,
    password character varying(128) NOT NULL,
    last_login timestamp with time zone,
    is_superuser boolean NOT NULL,
    username character varying(150) NOT NULL,
    first_name character varying(150) NOT NULL,
    last_name character varying(150) NOT NULL,
    email character varying(254) NOT NULL,
    is_staff boolean NOT NULL,
    is_active boolean NOT NULL,
    date_joined timestamp with time zone NOT NULL
);


ALTER TABLE public.auth_user OWNER TO postgres;

--
-- Name: auth_user_groups; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.auth_user_groups (
    id integer NOT NULL,
    user_id integer NOT NULL,
    group_id integer NOT NULL
);


ALTER TABLE public.auth_user_groups OWNER TO postgres;

--
-- Name: auth_user_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.auth_user_groups ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.auth_user_groups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: auth_user_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.auth_user ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.auth_user_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: auth_user_user_permissions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.auth_user_user_permissions (
    id integer NOT NULL,
    user_id integer NOT NULL,
    permission_id integer NOT NULL
);


ALTER TABLE public.auth_user_user_permissions OWNER TO postgres;

--
-- Name: auth_user_user_permissions_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.auth_user_user_permissions ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.auth_user_user_permissions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: authtoken_token; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.authtoken_token (
    key character varying(40) NOT NULL,
    created timestamp with time zone NOT NULL,
    user_id integer NOT NULL
);


ALTER TABLE public.authtoken_token OWNER TO postgres;

--
-- Name: django_admin_log; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.django_admin_log (
    id integer NOT NULL,
    action_time timestamp with time zone NOT NULL,
    object_id text,
    object_repr character varying(200) NOT NULL,
    action_flag smallint NOT NULL,
    change_message text NOT NULL,
    content_type_id integer,
    user_id integer NOT NULL,
    CONSTRAINT django_admin_log_action_flag_check CHECK ((action_flag >= 0))
);


ALTER TABLE public.django_admin_log OWNER TO postgres;

--
-- Name: django_admin_log_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.django_admin_log ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.django_admin_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: django_content_type; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.django_content_type (
    id integer NOT NULL,
    app_label character varying(100) NOT NULL,
    model character varying(100) NOT NULL
);


ALTER TABLE public.django_content_type OWNER TO postgres;

--
-- Name: django_content_type_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.django_content_type ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.django_content_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: django_migrations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.django_migrations (
    id integer NOT NULL,
    app character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    applied timestamp with time zone NOT NULL
);


ALTER TABLE public.django_migrations OWNER TO postgres;

--
-- Name: django_migrations_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.django_migrations ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.django_migrations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: django_session; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.django_session (
    session_key character varying(40) NOT NULL,
    session_data text NOT NULL,
    expire_date timestamp with time zone NOT NULL
);


ALTER TABLE public.django_session OWNER TO postgres;

--
-- Name: product_customer; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.product_customer (
    id character varying(200) NOT NULL,
    customer_name character varying(20),
    phone_no character varying(20),
    app_user_id character varying(20)
);


ALTER TABLE public.product_customer OWNER TO postgres;

--
-- Name: product_ecom_item_type; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.product_ecom_item_type (
    categories_id character varying(20) NOT NULL,
    categories_name character varying(200) NOT NULL,
    app_user_id character varying(20),
    app_data_time timestamp with time zone NOT NULL
);


ALTER TABLE public.product_ecom_item_type OWNER TO postgres;

--
-- Name: product_ecom_product_sub_categories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.product_ecom_product_sub_categories (
    subcategories_id character varying(20) NOT NULL,
    subcategories_name character varying(200) NOT NULL,
    app_user_id character varying(20),
    app_data_time timestamp with time zone NOT NULL,
    categories_id character varying(20)
);


ALTER TABLE public.product_ecom_product_sub_categories OWNER TO postgres;

--
-- Name: product_ecom_products; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.product_ecom_products (
    product_id character varying(20) NOT NULL,
    product_name character varying(200) NOT NULL,
    upload character varying(100) NOT NULL,
    product_model character varying(200),
    product_group character varying(200),
    product_price numeric(22,2),
    discount_amount numeric(22,2),
    product_old_price numeric(22,2),
    purchase_date date,
    product_feature character varying(500),
    stock_limit character varying(500),
    app_user_id character varying(20),
    app_data_time timestamp with time zone NOT NULL,
    agent_id character varying(200) NOT NULL,
    category_id character varying(20) NOT NULL,
    sub_category_id character varying(20) NOT NULL,
    unit_id character varying(20) NOT NULL
);


ALTER TABLE public.product_ecom_products OWNER TO postgres;

--
-- Name: product_payment_bank; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.product_payment_bank (
    bank_id character varying(200) NOT NULL,
    payment_bank character varying(20),
    app_user_id character varying(20),
    app_data_time timestamp with time zone NOT NULL
);


ALTER TABLE public.product_payment_bank OWNER TO postgres;

--
-- Name: product_payment_name; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.product_payment_name (
    paymenttype_id character varying(200) NOT NULL,
    payment_name character varying(20),
    app_user_id character varying(20),
    app_data_time timestamp with time zone NOT NULL
);


ALTER TABLE public.product_payment_name OWNER TO postgres;

--
-- Name: product_payment_type; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.product_payment_type (
    payment_id character varying(200) NOT NULL,
    payment_type character varying(200) NOT NULL,
    payment_amount numeric(22,2),
    check_bank character varying(200) NOT NULL,
    deposite_date date,
    reference_no character varying(200) NOT NULL,
    bank_account character varying(200),
    branch character varying(200) NOT NULL,
    app_user_id character varying(20)
);


ALTER TABLE public.product_payment_type OWNER TO postgres;

--
-- Name: product_products_unit; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.product_products_unit (
    unit_id character varying(20) NOT NULL,
    unit_name character varying(200) NOT NULL,
    is_active boolean NOT NULL,
    is_deleted boolean NOT NULL,
    app_user_id character varying(20) NOT NULL,
    app_data_time timestamp with time zone NOT NULL
);


ALTER TABLE public.product_products_unit OWNER TO postgres;

--
-- Name: product_sell_agents; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.product_sell_agents (
    agent_id character varying(200) NOT NULL,
    agent_name character varying(20),
    contact_no character varying(20),
    address character varying(20),
    email character varying(20),
    gmail character varying(20),
    app_user_id character varying(20),
    app_data_time timestamp with time zone NOT NULL
);


ALTER TABLE public.product_sell_agents OWNER TO postgres;

--
-- Data for Name: auth_group; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.auth_group (id, name) FROM stdin;
\.


--
-- Data for Name: auth_group_permissions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.auth_group_permissions (id, group_id, permission_id) FROM stdin;
\.


--
-- Data for Name: auth_permission; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.auth_permission (id, name, content_type_id, codename) FROM stdin;
1	Can add log entry	1	add_logentry
2	Can change log entry	1	change_logentry
3	Can delete log entry	1	delete_logentry
4	Can view log entry	1	view_logentry
5	Can add permission	2	add_permission
6	Can change permission	2	change_permission
7	Can delete permission	2	delete_permission
8	Can view permission	2	view_permission
9	Can add group	3	add_group
10	Can change group	3	change_group
11	Can delete group	3	delete_group
12	Can view group	3	view_group
13	Can add user	4	add_user
14	Can change user	4	change_user
15	Can delete user	4	delete_user
16	Can view user	4	view_user
17	Can add content type	5	add_contenttype
18	Can change content type	5	change_contenttype
19	Can delete content type	5	delete_contenttype
20	Can view content type	5	view_contenttype
21	Can add session	6	add_session
22	Can change session	6	change_session
23	Can delete session	6	delete_session
24	Can view session	6	view_session
25	Can add Token	7	add_token
26	Can change Token	7	change_token
27	Can delete Token	7	delete_token
28	Can view Token	7	view_token
29	Can add token	8	add_tokenproxy
30	Can change token	8	change_tokenproxy
31	Can delete token	8	delete_tokenproxy
32	Can view token	8	view_tokenproxy
33	Can add customer	9	add_customer
34	Can change customer	9	change_customer
35	Can delete customer	9	delete_customer
36	Can view customer	9	view_customer
37	Can add payment_bank	10	add_payment_bank
38	Can change payment_bank	10	change_payment_bank
39	Can delete payment_bank	10	delete_payment_bank
40	Can view payment_bank	10	view_payment_bank
41	Can add payment_name	11	add_payment_name
42	Can change payment_name	11	change_payment_name
43	Can delete payment_name	11	delete_payment_name
44	Can view payment_name	11	view_payment_name
45	Can add payment_type	12	add_payment_type
46	Can change payment_type	12	change_payment_type
47	Can delete payment_type	12	delete_payment_type
48	Can view payment_type	12	view_payment_type
49	Can add ecom_ products	13	add_ecom_products
50	Can change ecom_ products	13	change_ecom_products
51	Can delete ecom_ products	13	delete_ecom_products
52	Can view ecom_ products	13	view_ecom_products
53	Can add ecom_ product_ sub_ categories	14	add_ecom_product_sub_categories
54	Can change ecom_ product_ sub_ categories	14	change_ecom_product_sub_categories
55	Can delete ecom_ product_ sub_ categories	14	delete_ecom_product_sub_categories
56	Can view ecom_ product_ sub_ categories	14	view_ecom_product_sub_categories
57	Can add products_ unit	15	add_products_unit
58	Can change products_ unit	15	change_products_unit
59	Can delete products_ unit	15	delete_products_unit
60	Can view products_ unit	15	view_products_unit
61	Can add ecom_item_type	16	add_ecom_item_type
62	Can change ecom_item_type	16	change_ecom_item_type
63	Can delete ecom_item_type	16	delete_ecom_item_type
64	Can view ecom_item_type	16	view_ecom_item_type
65	Can add sell_ agents	17	add_sell_agents
66	Can change sell_ agents	17	change_sell_agents
67	Can delete sell_ agents	17	delete_sell_agents
68	Can view sell_ agents	17	view_sell_agents
\.


--
-- Data for Name: auth_user; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.auth_user (id, password, last_login, is_superuser, username, first_name, last_name, email, is_staff, is_active, date_joined) FROM stdin;
1	pbkdf2_sha256$390000$XL2P8a3LiFs6yyj7AiYeSI$BLILadccadI0M8A0NX8U7Y3bPkxhu0AS+nJ3NBs87S4=	2023-04-03 22:27:03.074244+06	t	simple				t	t	2023-04-03 22:26:50.31271+06
2	pbkdf2_sha256$390000$U5qVisMnd8OLAFn0Jfkxip$kIg+ecCjKIatdqVuNt+EeFHXCt+1rJ4ZnBuIEbeDgvw=	\N	t	mahbub				t	t	2023-04-03 22:46:17.649962+06
\.


--
-- Data for Name: auth_user_groups; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.auth_user_groups (id, user_id, group_id) FROM stdin;
\.


--
-- Data for Name: auth_user_user_permissions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.auth_user_user_permissions (id, user_id, permission_id) FROM stdin;
\.


--
-- Data for Name: authtoken_token; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.authtoken_token (key, created, user_id) FROM stdin;
\.


--
-- Data for Name: django_admin_log; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.django_admin_log (id, action_time, object_id, object_repr, action_flag, change_message, content_type_id, user_id) FROM stdin;
1	2023-04-03 22:29:12.723243+06	1	mahbub alam	1	[{"added": {}}]	17	1
2	2023-04-03 22:29:34.433912+06	2	tamim shahriair	1	[{"added": {}}]	17	1
3	2023-04-03 22:29:57.606146+06	1	pis	1	[{"added": {}}]	15	1
4	2023-04-03 22:30:07.463499+06	2	kg	1	[{"added": {}}]	15	1
5	2023-04-03 22:30:41.027665+06	1	cash	1	[{"added": {}}]	11	1
6	2023-04-03 22:31:58.583032+06	1	cash	2	[]	11	1
7	2023-04-03 22:32:17.869965+06	2	Bank_Deposite	1	[{"added": {}}]	11	1
8	2023-04-03 22:32:27.566286+06	3	cheque	1	[{"added": {}}]	11	1
9	2023-04-03 22:32:58.402944+06	1	Uttora Bank	1	[{"added": {}}]	10	1
10	2023-04-03 22:33:19.014696+06	2	Gramin Bank	1	[{"added": {}}]	10	1
11	2023-04-03 22:33:40.112088+06	3	Brack Bank	1	[{"added": {}}]	10	1
12	2023-04-03 22:33:58.494121+06	4	City Bank	1	[{"added": {}}]	10	1
13	2023-04-03 22:34:21.240819+06	5	EBL Bank	1	[{"added": {}}]	10	1
14	2023-04-03 22:54:38.180662+06	1	hardware	1	[{"added": {}}]	16	1
15	2023-04-03 22:54:46.925753+06	2	food and vegitable	1	[{"added": {}}]	16	1
16	2023-04-03 22:55:07.550472+06	1	laptop	1	[{"added": {}}]	14	1
17	2023-04-03 22:55:19.023342+06	2	apple	1	[{"added": {}}]	14	1
18	2023-04-03 23:10:58.543621+06	1	laptope	1	[{"added": {}}]	13	1
\.


--
-- Data for Name: django_content_type; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.django_content_type (id, app_label, model) FROM stdin;
1	admin	logentry
2	auth	permission
3	auth	group
4	auth	user
5	contenttypes	contenttype
6	sessions	session
7	authtoken	token
8	authtoken	tokenproxy
9	product	customer
10	product	payment_bank
11	product	payment_name
12	product	payment_type
13	product	ecom_products
14	product	ecom_product_sub_categories
15	product	products_unit
16	product	ecom_item_type
17	product	sell_agents
\.


--
-- Data for Name: django_migrations; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.django_migrations (id, app, name, applied) FROM stdin;
1	contenttypes	0001_initial	2023-04-03 22:11:02.9991+06
2	auth	0001_initial	2023-04-03 22:11:04.092465+06
3	admin	0001_initial	2023-04-03 22:11:04.328113+06
4	admin	0002_logentry_remove_auto_add	2023-04-03 22:11:04.364277+06
5	admin	0003_logentry_add_action_flag_choices	2023-04-03 22:11:04.394093+06
6	contenttypes	0002_remove_content_type_name	2023-04-03 22:11:04.443077+06
7	auth	0002_alter_permission_name_max_length	2023-04-03 22:11:04.456352+06
8	auth	0003_alter_user_email_max_length	2023-04-03 22:11:04.467753+06
9	auth	0004_alter_user_username_opts	2023-04-03 22:11:04.47767+06
10	auth	0005_alter_user_last_login_null	2023-04-03 22:11:04.488645+06
11	auth	0006_require_contenttypes_0002	2023-04-03 22:11:04.493182+06
12	auth	0007_alter_validators_add_error_messages	2023-04-03 22:11:04.503475+06
13	auth	0008_alter_user_username_max_length	2023-04-03 22:11:04.603961+06
14	auth	0009_alter_user_last_name_max_length	2023-04-03 22:11:04.62943+06
15	auth	0010_alter_group_name_max_length	2023-04-03 22:11:04.644203+06
16	auth	0011_update_proxy_permissions	2023-04-03 22:11:04.654225+06
17	auth	0012_alter_user_first_name_max_length	2023-04-03 22:11:04.66508+06
18	authtoken	0001_initial	2023-04-03 22:11:04.742513+06
19	authtoken	0002_auto_20160226_1747	2023-04-03 22:11:04.787393+06
20	authtoken	0003_tokenproxy	2023-04-03 22:11:04.793377+06
21	sessions	0001_initial	2023-04-03 22:11:04.900091+06
22	product	0001_initial	2023-04-03 22:17:38.684071+06
\.


--
-- Data for Name: django_session; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.django_session (session_key, session_data, expire_date) FROM stdin;
c6pdbi8dvio60su03jjs4v8fjtyx6llk	.eJxVjMEOwiAQRP-FsyEsAi0evfcbyO6yStXQpLQn47_bJj3obTLvzbxVwnUpaW0ypzGriwJ1-u0I-Sl1B_mB9T5pnuoyj6R3RR-06WHK8roe7t9BwVa2tUO6RTLgxQoHYAmGswXbgzdsYsiMdObQb9F64JhjdOQ738WAwVqnPl_lrTc-:1pjN1L:Bmqcrom32a19cRQi6ZQww9vmkNuTFrySH2rNFuFIc2o	2023-04-17 22:27:03.128097+06
\.


--
-- Data for Name: product_customer; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.product_customer (id, customer_name, phone_no, app_user_id) FROM stdin;
\.


--
-- Data for Name: product_ecom_item_type; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.product_ecom_item_type (categories_id, categories_name, app_user_id, app_data_time) FROM stdin;
1	hardware	admin	2023-04-03 22:54:38.178669+06
2	food and vegitable	admin	2023-04-03 22:54:46.924755+06
\.


--
-- Data for Name: product_ecom_product_sub_categories; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.product_ecom_product_sub_categories (subcategories_id, subcategories_name, app_user_id, app_data_time, categories_id) FROM stdin;
1	laptop	admin	2023-04-03 22:55:07.548704+06	1
2	apple	admin	2023-04-03 22:55:19.022346+06	2
\.


--
-- Data for Name: product_ecom_products; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.product_ecom_products (product_id, product_name, upload, product_model, product_group, product_price, discount_amount, product_old_price, purchase_date, product_feature, stock_limit, app_user_id, app_data_time, agent_id, category_id, sub_category_id, unit_id) FROM stdin;
1	laptope	uploads/download_1.jpg	vivo-f9	vivo-phone	60000.00	600.00	65000.00	2023-04-03	\N	9	admin	2023-04-03 23:10:58.471851+06	1	1	1	1
\.


--
-- Data for Name: product_payment_bank; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.product_payment_bank (bank_id, payment_bank, app_user_id, app_data_time) FROM stdin;
1	Uttora Bank	admin	2023-04-03 22:32:58.40095+06
2	Gramin Bank	admin	2023-04-03 22:33:19.014696+06
3	Brack Bank	admin	2023-04-03 22:33:40.11144+06
4	City Bank	admin	2023-04-03 22:33:58.494121+06
5	EBL Bank	admin	2023-04-03 22:34:21.239839+06
\.


--
-- Data for Name: product_payment_name; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.product_payment_name (paymenttype_id, payment_name, app_user_id, app_data_time) FROM stdin;
1	cash	admin	2023-04-03 22:30:41.026669+06
2	Bank_Deposite	admin	2023-04-03 22:32:17.867969+06
3	cheque	admin	2023-04-03 22:32:27.565249+06
\.


--
-- Data for Name: product_payment_type; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.product_payment_type (payment_id, payment_type, payment_amount, check_bank, deposite_date, reference_no, bank_account, branch, app_user_id) FROM stdin;
	1	1000.00	dhaka_bank	2023-04-30	1245	1		\N
\.


--
-- Data for Name: product_products_unit; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.product_products_unit (unit_id, unit_name, is_active, is_deleted, app_user_id, app_data_time) FROM stdin;
1	pis	t	f	admin	2023-04-03 22:29:57.604701+06
2	kg	t	f	admin	2023-04-03 22:30:07.462464+06
\.


--
-- Data for Name: product_sell_agents; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.product_sell_agents (agent_id, agent_name, contact_no, address, email, gmail, app_user_id, app_data_time) FROM stdin;
1	mahbub alam	01776879668	dhaka	triplover@email.com	\N	admin	2023-04-03 22:29:12.721549+06
2	tamim shahriair	098765432	dhaka,bangladesh.	akij@email.com	\N	admin	2023-04-03 22:29:34.433212+06
\.


--
-- Name: auth_group_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.auth_group_id_seq', 1, false);


--
-- Name: auth_group_permissions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.auth_group_permissions_id_seq', 1, false);


--
-- Name: auth_permission_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.auth_permission_id_seq', 68, true);


--
-- Name: auth_user_groups_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.auth_user_groups_id_seq', 1, false);


--
-- Name: auth_user_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.auth_user_id_seq', 2, true);


--
-- Name: auth_user_user_permissions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.auth_user_user_permissions_id_seq', 1, false);


--
-- Name: django_admin_log_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.django_admin_log_id_seq', 18, true);


--
-- Name: django_content_type_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.django_content_type_id_seq', 17, true);


--
-- Name: django_migrations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.django_migrations_id_seq', 22, true);


--
-- Name: auth_group auth_group_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auth_group
    ADD CONSTRAINT auth_group_name_key UNIQUE (name);


--
-- Name: auth_group_permissions auth_group_permissions_group_id_permission_id_0cd325b0_uniq; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_group_id_permission_id_0cd325b0_uniq UNIQUE (group_id, permission_id);


--
-- Name: auth_group_permissions auth_group_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_pkey PRIMARY KEY (id);


--
-- Name: auth_group auth_group_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auth_group
    ADD CONSTRAINT auth_group_pkey PRIMARY KEY (id);


--
-- Name: auth_permission auth_permission_content_type_id_codename_01ab375a_uniq; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auth_permission
    ADD CONSTRAINT auth_permission_content_type_id_codename_01ab375a_uniq UNIQUE (content_type_id, codename);


--
-- Name: auth_permission auth_permission_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auth_permission
    ADD CONSTRAINT auth_permission_pkey PRIMARY KEY (id);


--
-- Name: auth_user_groups auth_user_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auth_user_groups
    ADD CONSTRAINT auth_user_groups_pkey PRIMARY KEY (id);


--
-- Name: auth_user_groups auth_user_groups_user_id_group_id_94350c0c_uniq; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auth_user_groups
    ADD CONSTRAINT auth_user_groups_user_id_group_id_94350c0c_uniq UNIQUE (user_id, group_id);


--
-- Name: auth_user auth_user_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auth_user
    ADD CONSTRAINT auth_user_pkey PRIMARY KEY (id);


--
-- Name: auth_user_user_permissions auth_user_user_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permissions_pkey PRIMARY KEY (id);


--
-- Name: auth_user_user_permissions auth_user_user_permissions_user_id_permission_id_14a6b632_uniq; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permissions_user_id_permission_id_14a6b632_uniq UNIQUE (user_id, permission_id);


--
-- Name: auth_user auth_user_username_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auth_user
    ADD CONSTRAINT auth_user_username_key UNIQUE (username);


--
-- Name: authtoken_token authtoken_token_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.authtoken_token
    ADD CONSTRAINT authtoken_token_pkey PRIMARY KEY (key);


--
-- Name: authtoken_token authtoken_token_user_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.authtoken_token
    ADD CONSTRAINT authtoken_token_user_id_key UNIQUE (user_id);


--
-- Name: django_admin_log django_admin_log_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.django_admin_log
    ADD CONSTRAINT django_admin_log_pkey PRIMARY KEY (id);


--
-- Name: django_content_type django_content_type_app_label_model_76bd3d3b_uniq; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.django_content_type
    ADD CONSTRAINT django_content_type_app_label_model_76bd3d3b_uniq UNIQUE (app_label, model);


--
-- Name: django_content_type django_content_type_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.django_content_type
    ADD CONSTRAINT django_content_type_pkey PRIMARY KEY (id);


--
-- Name: django_migrations django_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.django_migrations
    ADD CONSTRAINT django_migrations_pkey PRIMARY KEY (id);


--
-- Name: django_session django_session_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.django_session
    ADD CONSTRAINT django_session_pkey PRIMARY KEY (session_key);


--
-- Name: product_customer product_customer_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_customer
    ADD CONSTRAINT product_customer_pkey PRIMARY KEY (id);


--
-- Name: product_ecom_item_type product_ecom_item_type_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_ecom_item_type
    ADD CONSTRAINT product_ecom_item_type_pkey PRIMARY KEY (categories_id);


--
-- Name: product_ecom_product_sub_categories product_ecom_product_sub_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_ecom_product_sub_categories
    ADD CONSTRAINT product_ecom_product_sub_categories_pkey PRIMARY KEY (subcategories_id);


--
-- Name: product_ecom_products product_ecom_products_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_ecom_products
    ADD CONSTRAINT product_ecom_products_pkey PRIMARY KEY (product_id);


--
-- Name: product_payment_bank product_payment_bank_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_payment_bank
    ADD CONSTRAINT product_payment_bank_pkey PRIMARY KEY (bank_id);


--
-- Name: product_payment_name product_payment_name_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_payment_name
    ADD CONSTRAINT product_payment_name_pkey PRIMARY KEY (paymenttype_id);


--
-- Name: product_payment_type product_payment_type_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_payment_type
    ADD CONSTRAINT product_payment_type_pkey PRIMARY KEY (payment_id);


--
-- Name: product_products_unit product_products_unit_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_products_unit
    ADD CONSTRAINT product_products_unit_pkey PRIMARY KEY (unit_id);


--
-- Name: product_sell_agents product_sell_agents_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_sell_agents
    ADD CONSTRAINT product_sell_agents_pkey PRIMARY KEY (agent_id);


--
-- Name: auth_group_name_a6ea08ec_like; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX auth_group_name_a6ea08ec_like ON public.auth_group USING btree (name varchar_pattern_ops);


--
-- Name: auth_group_permissions_group_id_b120cbf9; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX auth_group_permissions_group_id_b120cbf9 ON public.auth_group_permissions USING btree (group_id);


--
-- Name: auth_group_permissions_permission_id_84c5c92e; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX auth_group_permissions_permission_id_84c5c92e ON public.auth_group_permissions USING btree (permission_id);


--
-- Name: auth_permission_content_type_id_2f476e4b; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX auth_permission_content_type_id_2f476e4b ON public.auth_permission USING btree (content_type_id);


--
-- Name: auth_user_groups_group_id_97559544; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX auth_user_groups_group_id_97559544 ON public.auth_user_groups USING btree (group_id);


--
-- Name: auth_user_groups_user_id_6a12ed8b; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX auth_user_groups_user_id_6a12ed8b ON public.auth_user_groups USING btree (user_id);


--
-- Name: auth_user_user_permissions_permission_id_1fbb5f2c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX auth_user_user_permissions_permission_id_1fbb5f2c ON public.auth_user_user_permissions USING btree (permission_id);


--
-- Name: auth_user_user_permissions_user_id_a95ead1b; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX auth_user_user_permissions_user_id_a95ead1b ON public.auth_user_user_permissions USING btree (user_id);


--
-- Name: auth_user_username_6821ab7c_like; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX auth_user_username_6821ab7c_like ON public.auth_user USING btree (username varchar_pattern_ops);


--
-- Name: authtoken_token_key_10f0b77e_like; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX authtoken_token_key_10f0b77e_like ON public.authtoken_token USING btree (key varchar_pattern_ops);


--
-- Name: django_admin_log_content_type_id_c4bce8eb; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX django_admin_log_content_type_id_c4bce8eb ON public.django_admin_log USING btree (content_type_id);


--
-- Name: django_admin_log_user_id_c564eba6; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX django_admin_log_user_id_c564eba6 ON public.django_admin_log USING btree (user_id);


--
-- Name: django_session_expire_date_a5c62663; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX django_session_expire_date_a5c62663 ON public.django_session USING btree (expire_date);


--
-- Name: django_session_session_key_c0390e0f_like; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX django_session_session_key_c0390e0f_like ON public.django_session USING btree (session_key varchar_pattern_ops);


--
-- Name: product_customer_id_d551848a_like; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX product_customer_id_d551848a_like ON public.product_customer USING btree (id varchar_pattern_ops);


--
-- Name: product_ecom_item_type_categories_id_1be3fcc0_like; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX product_ecom_item_type_categories_id_1be3fcc0_like ON public.product_ecom_item_type USING btree (categories_id varchar_pattern_ops);


--
-- Name: product_ecom_product_sub_categories_categories_id_bb9dbefb; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX product_ecom_product_sub_categories_categories_id_bb9dbefb ON public.product_ecom_product_sub_categories USING btree (categories_id);


--
-- Name: product_ecom_product_sub_categories_categories_id_bb9dbefb_like; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX product_ecom_product_sub_categories_categories_id_bb9dbefb_like ON public.product_ecom_product_sub_categories USING btree (categories_id varchar_pattern_ops);


--
-- Name: product_ecom_product_sub_subcategories_id_57ccefee_like; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX product_ecom_product_sub_subcategories_id_57ccefee_like ON public.product_ecom_product_sub_categories USING btree (subcategories_id varchar_pattern_ops);


--
-- Name: product_ecom_products_agent_id_a8a17d8f; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX product_ecom_products_agent_id_a8a17d8f ON public.product_ecom_products USING btree (agent_id);


--
-- Name: product_ecom_products_agent_id_a8a17d8f_like; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX product_ecom_products_agent_id_a8a17d8f_like ON public.product_ecom_products USING btree (agent_id varchar_pattern_ops);


--
-- Name: product_ecom_products_category_id_b57854a7; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX product_ecom_products_category_id_b57854a7 ON public.product_ecom_products USING btree (category_id);


--
-- Name: product_ecom_products_category_id_b57854a7_like; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX product_ecom_products_category_id_b57854a7_like ON public.product_ecom_products USING btree (category_id varchar_pattern_ops);


--
-- Name: product_ecom_products_product_id_bfc03cf1_like; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX product_ecom_products_product_id_bfc03cf1_like ON public.product_ecom_products USING btree (product_id varchar_pattern_ops);


--
-- Name: product_ecom_products_sub_category_id_991c7f74; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX product_ecom_products_sub_category_id_991c7f74 ON public.product_ecom_products USING btree (sub_category_id);


--
-- Name: product_ecom_products_sub_category_id_991c7f74_like; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX product_ecom_products_sub_category_id_991c7f74_like ON public.product_ecom_products USING btree (sub_category_id varchar_pattern_ops);


--
-- Name: product_ecom_products_unit_id_f64dc725; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX product_ecom_products_unit_id_f64dc725 ON public.product_ecom_products USING btree (unit_id);


--
-- Name: product_ecom_products_unit_id_f64dc725_like; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX product_ecom_products_unit_id_f64dc725_like ON public.product_ecom_products USING btree (unit_id varchar_pattern_ops);


--
-- Name: product_payment_bank_bank_id_e4bbb035_like; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX product_payment_bank_bank_id_e4bbb035_like ON public.product_payment_bank USING btree (bank_id varchar_pattern_ops);


--
-- Name: product_payment_name_paymenttype_id_a852fa03_like; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX product_payment_name_paymenttype_id_a852fa03_like ON public.product_payment_name USING btree (paymenttype_id varchar_pattern_ops);


--
-- Name: product_payment_type_payment_id_27104612_like; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX product_payment_type_payment_id_27104612_like ON public.product_payment_type USING btree (payment_id varchar_pattern_ops);


--
-- Name: product_products_unit_unit_id_5582c7c5_like; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX product_products_unit_unit_id_5582c7c5_like ON public.product_products_unit USING btree (unit_id varchar_pattern_ops);


--
-- Name: product_sell_agents_agent_id_ad952928_like; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX product_sell_agents_agent_id_ad952928_like ON public.product_sell_agents USING btree (agent_id varchar_pattern_ops);


--
-- Name: auth_group_permissions auth_group_permissio_permission_id_84c5c92e_fk_auth_perm; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissio_permission_id_84c5c92e_fk_auth_perm FOREIGN KEY (permission_id) REFERENCES public.auth_permission(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_group_permissions auth_group_permissions_group_id_b120cbf9_fk_auth_group_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_group_id_b120cbf9_fk_auth_group_id FOREIGN KEY (group_id) REFERENCES public.auth_group(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_permission auth_permission_content_type_id_2f476e4b_fk_django_co; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auth_permission
    ADD CONSTRAINT auth_permission_content_type_id_2f476e4b_fk_django_co FOREIGN KEY (content_type_id) REFERENCES public.django_content_type(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_user_groups auth_user_groups_group_id_97559544_fk_auth_group_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auth_user_groups
    ADD CONSTRAINT auth_user_groups_group_id_97559544_fk_auth_group_id FOREIGN KEY (group_id) REFERENCES public.auth_group(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_user_groups auth_user_groups_user_id_6a12ed8b_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auth_user_groups
    ADD CONSTRAINT auth_user_groups_user_id_6a12ed8b_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_user_user_permissions auth_user_user_permi_permission_id_1fbb5f2c_fk_auth_perm; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permi_permission_id_1fbb5f2c_fk_auth_perm FOREIGN KEY (permission_id) REFERENCES public.auth_permission(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_user_user_permissions auth_user_user_permissions_user_id_a95ead1b_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permissions_user_id_a95ead1b_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: authtoken_token authtoken_token_user_id_35299eff_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.authtoken_token
    ADD CONSTRAINT authtoken_token_user_id_35299eff_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: django_admin_log django_admin_log_content_type_id_c4bce8eb_fk_django_co; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.django_admin_log
    ADD CONSTRAINT django_admin_log_content_type_id_c4bce8eb_fk_django_co FOREIGN KEY (content_type_id) REFERENCES public.django_content_type(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: django_admin_log django_admin_log_user_id_c564eba6_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.django_admin_log
    ADD CONSTRAINT django_admin_log_user_id_c564eba6_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: product_ecom_products product_ecom_product_agent_id_a8a17d8f_fk_product_s; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_ecom_products
    ADD CONSTRAINT product_ecom_product_agent_id_a8a17d8f_fk_product_s FOREIGN KEY (agent_id) REFERENCES public.product_sell_agents(agent_id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: product_ecom_product_sub_categories product_ecom_product_categories_id_bb9dbefb_fk_product_e; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_ecom_product_sub_categories
    ADD CONSTRAINT product_ecom_product_categories_id_bb9dbefb_fk_product_e FOREIGN KEY (categories_id) REFERENCES public.product_ecom_item_type(categories_id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: product_ecom_products product_ecom_product_category_id_b57854a7_fk_product_e; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_ecom_products
    ADD CONSTRAINT product_ecom_product_category_id_b57854a7_fk_product_e FOREIGN KEY (category_id) REFERENCES public.product_ecom_item_type(categories_id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: product_ecom_products product_ecom_product_sub_category_id_991c7f74_fk_product_e; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_ecom_products
    ADD CONSTRAINT product_ecom_product_sub_category_id_991c7f74_fk_product_e FOREIGN KEY (sub_category_id) REFERENCES public.product_ecom_product_sub_categories(subcategories_id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: product_ecom_products product_ecom_product_unit_id_f64dc725_fk_product_p; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_ecom_products
    ADD CONSTRAINT product_ecom_product_unit_id_f64dc725_fk_product_p FOREIGN KEY (unit_id) REFERENCES public.product_products_unit(unit_id) DEFERRABLE INITIALLY DEFERRED;


--
-- PostgreSQL database dump complete
--

