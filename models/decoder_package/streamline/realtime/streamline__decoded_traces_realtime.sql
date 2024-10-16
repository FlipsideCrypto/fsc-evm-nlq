{# Set variables #}
{%- set model_name = 'DECODED_TRACES' -%}
{%- set model_type = 'REALTIME' -%}

{%- set default_vars = set_default_variables_streamline_decoder(model_name, model_type) -%}

{# Set up parameters for the streamline process. These will come from the vars set in dbt_project.yml #}
{%- set streamline_params = set_streamline_parameters_decoder(
    model_name=model_name,
    model_type=model_type
) -%}

{%- set testing_limit = default_vars['testing_limit'] -%}

{# Log configuration details #}
{{ log_streamline_details(
    model_name=model_name,
    model_type=model_type,
    testing_limit=testing_limit,
    streamline_params=streamline_params
) }}

{# Set up dbt configuration #}
{{ config (
    materialized = "view",
    post_hook = [fsc_utils.if_data_call_function_v2(
        func = 'streamline.udf_bulk_decode_traces_v2',
        target = "{{this.schema}}.{{this.identifier}}",
        params = streamline_params
    ),
    fsc_utils.if_data_call_wait()],
    tags = ['streamline_' ~ model_name.lower() ~ '_' ~ model_type.lower()]
) }}

{# Main query starts here #}
{{ streamline_decoded_traces_requests(
    model_type = model_type.lower(),
    testing_limit = testing_limit
) }}