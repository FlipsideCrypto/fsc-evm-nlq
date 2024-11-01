{% macro decode_historical_logs(backfill_mode=false) %}

  {%- set params = {
      "sql_limit": var("HISTORICAL_DECODING_SQL_LIMIT", 20),
      "producer_batch_size": var("HISTORICAL_DECODING_PRODUCER_BATCH_SIZE", 400000),
      "worker_batch_size": var("HISTORICAL_DECODING_WORKER_BATCH_SIZE", 200000)
  } -%}

  {% set wait_time = var("HISTORICAL_DECODING_WAIT_TIME", 60) %}

  {% set find_months_query %}
    SELECT 
      DISTINCT date_trunc('month', block_timestamp)::date as month
    FROM {{ ref('core__fact_blocks') }}
    ORDER BY 1 ASC
  {% endset %}

  {% set results = run_query(find_months_query) %}

  {% if execute %}
    {% set months = results.columns[0].values() %}
    
    {% for month in months %}
      {% set view_name = 'decode_historical_logs_' ~ month.strftime('%Y_%m') %}
      
      {% set create_view_query %}
        create or replace view streamline.{{view_name}} as (
          WITH target_blocks AS (
              SELECT 
                  block_number
              FROM {{ ref('core__fact_blocks') }}
              WHERE date_trunc('month', block_timestamp) = '{{month}}'::timestamp
          ),
          new_abis AS (
              SELECT *
              FROM {{ ref('silver__complete_event_abis') }} 
              {% if not backfill_mode %}
                WHERE inserted_timestamp > dateadd('day', -30, sysdate())
              {% endif %}
          ),
          existing_logs_to_exclude AS (
              SELECT _log_id
              FROM {{ ref('streamline__decoded_logs_complete') }} l
              INNER JOIN target_blocks b using (block_number)
          ),
          candidate_logs AS (
              SELECT 
                  l.block_number,
                  l.tx_hash,
                  l.event_index,
                  l.contract_address,
                  l.topics,
                  l.data,
                  concat(l.tx_hash::string, '-', l.event_index::string) as _log_id
              FROM target_blocks b
              JOIN {{ ref('core__fact_event_logs') }} l using (block_number)
              WHERE l.tx_succeeded and date_trunc('month', l.block_timestamp) = '{{month}}'::timestamp
          )
          SELECT
            l.block_number,
            l._log_id,
            A.abi,
            OBJECT_CONSTRUCT(
              'topics', l.topics,
              'data', l.data,
              'address', l.contract_address
            ) AS data
          FROM candidate_logs l
          INNER JOIN new_abis A
            ON A.parent_contract_address = l.contract_address
            AND A.event_signature = l.topics[0]::STRING
            AND l.block_number BETWEEN A.start_block AND A.end_block
          WHERE NOT EXISTS (
              SELECT 1 
              FROM existing_logs_to_exclude e 
              WHERE e._log_id = l._log_id
          )
          LIMIT {{ params.sql_limit }}
        )
      {% endset %}

      {# Create the view #}
      {% do run_query(create_view_query) %}
      {{ log("Created view for month " ~ month.strftime('%Y-%m'), info=True) }}
      
      {% if var("STREAMLINE_INVOKE_STREAMS", false) %}
        {# Invoke streamline, if rows exist to decode #}
        {% set decode_query %}
          SELECT
            streamline.udf_bulk_decode_logs_v2(
              PARSE_JSON(
                  $${ "external_table": "decoded_logs",
                  "producer_batch_size": {{ params.producer_batch_size }},
                  "sql_limit": {{ params.sql_limit }},
                  "sql_source": "{{view_name}}",
                  "worker_batch_size": {{ params.worker_batch_size }} }$$
              )
            )
          WHERE
            EXISTS(
              SELECT 1
              FROM streamline.{{view_name}}
              LIMIT 1
            );
        {% endset %}
        
        {% do run_query(decode_query) %}
        {{ log("Triggered decoding for month " ~ month.strftime('%Y-%m'), info=True) }}
        
        {# Call wait to avoid queueing up too many jobs #}
        {% do run_query("call system$wait(" ~ wait_time ~ ")") %}
        {{ log("Completed wait after decoding for month " ~ month.strftime('%Y-%m'), info=True) }}
      {% endif %}
      
    {% endfor %}
  {% endif %}

{% endmacro %}