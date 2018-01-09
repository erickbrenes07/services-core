BEGIN;
    -- insert seed data for basic user/platform/project/reward
    \i /specs/sql-support/insert_platform_user_project.sql
    \i /specs/sql-support/payment_json_build_helpers.sql

    select plan(7);

    SELECT function_returns(
        'notification_service', '_generate_template_vars_from_relations', ARRAY['json'], 'json'
    );

    create or replace function test_with_user_relations()
    returns setof text language plpgsql as $$
    declare
        _relations_json json;
        _user community_service.users;
        _payment payment_service.catalog_payments;
        _result json;
    begin

        -- generate payment
        insert into payment_service.catalog_payments
        (gateway, platform_id, user_id, reward_id, project_id, data) 
        values ('pagarme', __seed_platform_id(), __seed_first_user_id(), __seed_reward_id(), __seed_project_id(), '{}')
        returning * into _payment;

        _relations_json := json_build_object(
            'user_id', __seed_first_user_id(),
            'project_id', __seed_project_id(),
            'reward_id', __seed_reward_id(),
            'catalog_payment_id', _payment.id
        );

        _result := notification_service._generate_template_vars_from_relations(_relations_json);

        return next ok(
            (_result->'user')::jsonb ?& '{id, name, email, document_type, document_number, created_at, fmt_created_at}',
            'check user structure keys'
        );

        return next ok(
            (_result->'payment')::jsonb ?& '{id, amount, boleto_url, boleto_barcode, boleto_expiration_date, boleto_expiration_day_month, payment_method, confirmed_at, fmt_confirmed_at, refused_at, fmt_refused_at, chargedback_at, fmt_chargedback_at, refunded_at, fmt_refunded_at, next_charge_at, fmt_next_charge_at, card_last_digits, card_brand, created_at, fmt_created_at}',
            'check payment structure keys'
        );

        return next ok(
            (_result->'project')::jsonb ?& '{id, name, mode, permalink, expires_at, fmt_expires_at, video_info, online_days, card_info, total_paid_in_contributions, total_paid_in_active_subscriptions, total_contributors, total_contributions, total_subscriptions}',
            'check project structure keys'
        );

        return next ok(
            (_result->'reward')::jsonb ?& '{id, title, minimum_value, deliver_at, fmt_deliver_at, deliver_at_period}',
            'check reward structure keys'
        );

        return next ok(
            (_result->'platform')::jsonb ?& '{id, name}',
            'check platform structure keys'
        );


        return next ok(
            (_result->'project_owner')::jsonb ?& '{id, name, email, document_type, document_number, created_at, fmt_created_at}',
            'check project_owner structure keys'
        );

    end;
    $$;

    select test_with_user_relations();

    SELECT * FROM finish();
ROLLBACK;
