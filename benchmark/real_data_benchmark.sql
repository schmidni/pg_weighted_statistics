WITH damage_data AS (
            SELECT
                lat.name as tag_name,
                rv.dg1_value,
                rv.dg2_value,
                rv.dg3_value,
                rv.dg4_value,
                rv.dg5_value,
                rv.weight
            FROM loss_riskvalue rv
            INNER JOIN loss_assoc_riskvalue_aggregationtag assoc ON
                rv._oid = assoc.riskvalue
                AND rv._calculation_oid = assoc._calculation_oid
                AND rv.losscategory = assoc.losscategory
            INNER JOIN loss_aggregationtag lat ON
                         assoc.aggregationtag = lat._oid
            WHERE
                rv._calculation_oid = 2
                AND rv.losscategory = 'BUSINESS_INTERRUPTION'
                AND rv._type = 'DAMAGE'
                AND assoc.aggregationtype = 'CantonGemeinde'
                AND lat.name LIKE 'AG%'
        ),
        damage_statistics AS (
            SELECT
                tag_name,
                -- All damage grade statistics using sparse data functions
                weighted_mean(array_agg(dg1_value),
                    array_agg(weight)) as dg1_mean,
                weighted_quantile(array_agg(dg1_value),
                    array_agg(weight), ARRAY[0.1, 0.9]) as dg1_quantiles,

                weighted_mean(array_agg(dg2_value),
                    array_agg(weight)) as dg2_mean,
                weighted_quantile(array_agg(dg2_value),
                    array_agg(weight), ARRAY[0.1, 0.9]) as dg2_quantiles,

                weighted_mean(array_agg(dg3_value),
                    array_agg(weight)) as dg3_mean,
                weighted_quantile(array_agg(dg3_value),
                    array_agg(weight), ARRAY[0.1, 0.9]) as dg3_quantiles,

                weighted_mean(array_agg(dg4_value),
                    array_agg(weight)) as dg4_mean,
                weighted_quantile(array_agg(dg4_value),
                    array_agg(weight), ARRAY[0.1, 0.9]) as dg4_quantiles,

                weighted_mean(array_agg(dg5_value),
                    array_agg(weight)) as dg5_mean,
                weighted_quantile(array_agg(dg5_value),
                    array_agg(weight), ARRAY[0.1, 0.9]) as dg5_quantiles
            FROM damage_data
            GROUP BY tag_name
        ),
        all_tags AS (
            SELECT DISTINCT lat.name as tag_name
            FROM loss_aggregationtag lat
            INNER JOIN loss_aggregationgeometry geom ON
                geom._aggregationtag_oid = lat._oid
            WHERE
                lat.type = 'CantonGemeinde'
                AND lat.name LIKE 'AG%'
                AND geom._exposuremodel_oid IN (
                    SELECT _exposuremodel_oid
                    FROM loss_calculationbranch
                    WHERE _calculation_oid = 2
                )
        ),
        building_counts AS (
            SELECT
                lat.name as tag_name,
                SUM(ast.buildingcount) as total_buildings
            FROM loss_aggregationtag lat
            INNER JOIN loss_assoc_asset_aggregationtag assoc ON
                lat._oid = assoc.aggregationtag
            INNER JOIN loss_asset ast ON assoc.asset = ast._oid
            INNER JOIN (
                SELECT _exposuremodel_oid
                FROM loss_calculationbranch
                WHERE _calculation_oid = 2
                LIMIT 1
            ) exp_sub ON ast._exposuremodel_oid = exp_sub._exposuremodel_oid
            WHERE
                lat.type = 'CantonGemeinde'
                AND lat.name LIKE 'AG%'
            GROUP BY lat.name
        )
        SELECT
            'BUSINESS_INTERRUPTION' as category,
            ARRAY[at.tag_name] as tag,
            COALESCE(ROUND(ds.dg1_mean::numeric, 5), 0) as dg1_mean,
            COALESCE(ROUND(ds.dg1_quantiles[1]::numeric, 5), 0) as dg1_pc10,
            COALESCE(ROUND(ds.dg1_quantiles[2]::numeric, 5), 0) as dg1_pc90,
            COALESCE(ROUND(ds.dg2_mean::numeric, 5), 0) as dg2_mean,
            COALESCE(ROUND(ds.dg2_quantiles[1]::numeric, 5), 0) as dg2_pc10,
            COALESCE(ROUND(ds.dg2_quantiles[2]::numeric, 5), 0) as dg2_pc90,
            COALESCE(ROUND(ds.dg3_mean::numeric, 5), 0) as dg3_mean,
            COALESCE(ROUND(ds.dg3_quantiles[1]::numeric, 5), 0) as dg3_pc10,
            COALESCE(ROUND(ds.dg3_quantiles[2]::numeric, 5), 0) as dg3_pc90,
            COALESCE(ROUND(ds.dg4_mean::numeric, 5), 0) as dg4_mean,
            COALESCE(ROUND(ds.dg4_quantiles[1]::numeric, 5), 0) as dg4_pc10,
            COALESCE(ROUND(ds.dg4_quantiles[2]::numeric, 5), 0) as dg4_pc90,
            COALESCE(ROUND(ds.dg5_mean::numeric, 5), 0) as dg5_mean,
            COALESCE(ROUND(ds.dg5_quantiles[1]::numeric, 5), 0) as dg5_pc10,
            COALESCE(ROUND(ds.dg5_quantiles[2]::numeric, 5), 0) as dg5_pc90,
            COALESCE(bc.total_buildings::numeric, 0) as buildings
        FROM all_tags at
        LEFT JOIN damage_statistics ds ON at.tag_name = ds.tag_name
        LEFT JOIN building_counts bc ON at.tag_name = bc.tag_name
        ORDER BY at.tag_name