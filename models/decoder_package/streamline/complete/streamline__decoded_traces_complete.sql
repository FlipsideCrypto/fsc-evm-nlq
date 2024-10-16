{# Set variables #}
{%- set source_name = 'DECODED_TRACES' -%}
{%- set model_type = 'COMPLETE' -%}

{%- set full_refresh_type = var((source_name ~ '_complete_full_refresh').upper(), False) -%}

{% set post_hook = "ALTER TABLE {{ this }} ADD SEARCH OPTIMIZATION on equality(_call_id)" %}
{% set unique_key = "_call_id" %}

{# Log configuration details #}
{{ log_complete_details(
    post_hook = post_hook,
    full_refresh_type = full_refresh_type
) }}

{# Set up dbt configuration #}
-- depends_on: {{ ref('bronze__' ~ source_name.lower()) }}

{{ config (
    materialized = "incremental",
    unique_key = unique_key,
    cluster_by = "ROUND(block_number, -3)",
    incremental_predicates = ["dynamic_range", "block_number"],
    merge_update_columns = [unique_key],
    post_hook = post_hook,
    full_refresh = full_refresh_type,
    tags = ['streamline_' ~ source_name.lower() ~ '_' ~ model_type.lower()]
) }}

{# Main query starts here #}
SELECT
    block_number,
    file_name,
    id AS {{ unique_key }},
    {{ dbt_utils.generate_surrogate_key(['id']) }} AS complete_{{ source_name.lower() }}_id,
    SYSDATE() AS inserted_timestamp,
    SYSDATE() AS modified_timestamp,
    _inserted_timestamp,
    '{{ invocation_id }}' AS _invocation_id
FROM
    {% if is_incremental() %}
        {{ ref('bronze__' ~ source_name.lower()) }}
    WHERE
        _inserted_timestamp >= (
            SELECT
                COALESCE(MAX(_inserted_timestamp), '1970-01-01'::TIMESTAMP) AS _inserted_timestamp
            FROM
                {{ this }}
        )
    {% else %}
        {{ ref('bronze__' ~ source_name.lower() ~ '_fr') }}
    {% endif %}

QUALIFY (ROW_NUMBER() OVER (PARTITION BY id ORDER BY _inserted_timestamp DESC)) = 1
