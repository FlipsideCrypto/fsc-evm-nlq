{%- if var('GLOBAL_ENABLE_FSC_EVM', False) -%}

{{ config(
    materialized = 'ephemeral'
) }}

WITH base AS (
    SELECT
        DATE_TRUNC(
            'hour',
            block_timestamp
        ) AS block_hour,
        MAX(block_number) AS block_number
    FROM
        {{ ref("silver__blocks") }}
    WHERE
        block_timestamp > DATEADD(
            'day',
            -5,
            CURRENT_DATE
        )
    GROUP BY
        1
)
SELECT
    block_hour,
    block_number
FROM
    base
WHERE
    block_hour <> (
        SELECT
            MAX(
                block_hour
            )
        FROM
            base
    )
{%- endif -%}