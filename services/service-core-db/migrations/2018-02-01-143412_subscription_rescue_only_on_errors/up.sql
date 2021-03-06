-- Your SQL goes here
CREATE OR REPLACE FUNCTION payment_service.subscriptions_server_error_rescue_charge()
 RETURNS json
 LANGUAGE plpgsql
AS $function$
    declare
        _result json;
        _affected_subscriptions_ids uuid[];
        _total_affected integer;
        _subscription_payment payment_service.catalog_payments;
    begin
        _total_affected := 0;
        
        for _subscription_payment IN (select last_payment.*
            from payment_service.subscriptions s
            join lateral (
                select *
                from payment_service.catalog_payments cp
                where cp.subscription_id = s.id
                order by created_at desc
                limit 1
            ) as last_payment on true
            where s.status = 'active' and last_payment.status in('error') 
            and last_payment.error_retry_at is null
            and (
                case last_payment.status
                when 'error' then
                    last_payment.gateway_cached_data is null 
                    OR (
                        (select true from json_array_elements_text(last_payment.gateway_cached_data::json) as el
                            where el::json ->> 'message' ~* 'error'
                            and el::json ->> 'type' is null) AND json_array_length(last_payment.gateway_cached_data::json) = 1
                    )
                else 
                    last_payment.gateway_cached_data is null
                end
            ) 
        )
        loop
            perform pg_notify('process_payments_channel',
                json_build_object(
                    'id', _subscription_payment.id, 
                    'subscription_id', _subscription_payment.subscription_id,
                    'rescued_at', now()
                )::text);

            update payment_service.catalog_payments
                set error_retry_at = now()
                where id = _subscription_payment.id;

            _total_affected := _total_affected + 1;
            _affected_subscriptions_ids := array_append(_affected_subscriptions_ids, _subscription_payment.subscription_id);        
        end loop;

        _result := json_build_object(
            'total_affected', _total_affected,
            'affected_ids', _affected_subscriptions_ids
        );

        return _result;
    end;
$function$
