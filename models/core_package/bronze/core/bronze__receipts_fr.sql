{{ config (
    materialized = 'view',
    tags = ['core']
) }}

SELECT
    partition_key,
    block_number,
    array_index,
    VALUE,
    DATA,
    metadata,
    file_name,
    _inserted_timestamp
FROM
    {{ ref('bronze__receipts_fr_v2') }}
{% if var('GLOBAL_USES_STREAMLINE_V1') %}
UNION ALL
SELECT
    _partition_by_block_id AS partition_key,
    block_number,
    VALUE :"array_index" :: INT AS array_index,
    VALUE,
    DATA,
    metadata,
    file_name,
    _inserted_timestamp
FROM
   {{ ref('bronze__receipts_fr_v1') }}
{% endif %}