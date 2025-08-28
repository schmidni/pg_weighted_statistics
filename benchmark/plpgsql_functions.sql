-- PL/pgSQL Reference Implementations for Performance Comparison
--
-- These are simple PL/pgSQL implementations to serve as performance baselines
-- for comparing against the optimized C implementations.

-- Weighted Mean (PL/pgSQL baseline)
CREATE OR REPLACE FUNCTION weighted_mean_plpgsql(
    vals double precision[],
    weights double precision[]
)
RETURNS double precision
LANGUAGE plpgsql
IMMUTABLE STRICT
AS $$
DECLARE
    i INTEGER;
    weighted_sum double precision := 0;
    weight_sum double precision := 0;
    missing_weight double precision;
BEGIN
    IF array_length(vals, 1) != array_length(weights, 1) THEN
        RAISE EXCEPTION 'Arrays must have same length';
    END IF;
    
    FOR i IN 1..array_length(vals, 1) LOOP
        weighted_sum := weighted_sum + vals[i] * weights[i];
        weight_sum := weight_sum + weights[i];
    END LOOP;
    
    -- Handle sparse data (add implicit zeros)
    missing_weight := 1.0 - weight_sum;
    IF missing_weight > 0 THEN
        weight_sum := 1.0;
    END IF;
    
    RETURN weighted_sum / weight_sum;
END;
$$;

-- Weighted Variance (PL/pgSQL baseline)
CREATE OR REPLACE FUNCTION weighted_variance_plpgsql(
    vals double precision[],
    weights double precision[],
    ddof INTEGER DEFAULT 0
)
RETURNS double precision
LANGUAGE plpgsql
IMMUTABLE STRICT
AS $$
DECLARE
    i INTEGER;
    mean_val double precision;
    weighted_sum_sq double precision := 0;
    weight_sum double precision := 0;
    missing_weight double precision;
    effective_n double precision;
BEGIN
    IF array_length(vals, 1) != array_length(weights, 1) THEN
        RAISE EXCEPTION 'Arrays must have same length';
    END IF;
    
    -- Calculate weighted mean first
    mean_val := weighted_mean_plpgsql(vals, weights);
    
    FOR i IN 1..array_length(vals, 1) LOOP
        weighted_sum_sq := weighted_sum_sq + weights[i] * pow(vals[i] - mean_val, 2);
        weight_sum := weight_sum + weights[i];
    END LOOP;
    
    -- Handle sparse data (add implicit zeros)
    missing_weight := 1.0 - weight_sum;
    IF missing_weight > 0 THEN
        weighted_sum_sq := weighted_sum_sq + missing_weight * pow(0 - mean_val, 2);
        weight_sum := 1.0;
    END IF;
    
    -- Apply degrees of freedom correction
    effective_n := weight_sum;
    IF ddof > 0 THEN
        effective_n := weight_sum - ddof;
    END IF;
    
    IF effective_n <= 0 THEN
        RETURN 0;  -- Avoid division by zero
    END IF;
    
    RETURN weighted_sum_sq / effective_n;
END;
$$;

-- Weighted Standard Deviation (PL/pgSQL baseline)
CREATE OR REPLACE FUNCTION weighted_std_plpgsql(
    vals double precision[],
    weights double precision[],
    ddof INTEGER DEFAULT 0
)
RETURNS double precision
LANGUAGE plpgsql
IMMUTABLE STRICT
AS $$
BEGIN
    RETURN sqrt(weighted_variance_plpgsql(vals, weights, ddof));
END;
$$;

-- Weighted Quantile (PL/pgSQL baseline) - Optimized implementation
CREATE OR REPLACE FUNCTION weighted_quantile_plpgsql(
    vals DOUBLE PRECISION[],
    weights DOUBLE PRECISION[],
    quantiles DOUBLE PRECISION[]
) RETURNS DOUBLE PRECISION[] AS $$
DECLARE
    n INTEGER;
    total_weight DOUBLE PRECISION := 0.0;
    zero_weight DOUBLE PRECISION;
    sorted_data DOUBLE PRECISION[][];
    cumsum DOUBLE PRECISION := 0.0;
    result DOUBLE PRECISION[] := '{}';
    q DOUBLE PRECISION;
    target_weight DOUBLE PRECISION;
    i INTEGER;
    j INTEGER;
    lower_val DOUBLE PRECISION;
    upper_val DOUBLE PRECISION;
    lower_cum DOUBLE PRECISION;
    upper_cum DOUBLE PRECISION;
    interp_factor DOUBLE PRECISION;
BEGIN
    -- Handle NULL or empty arrays
    IF vals IS NULL OR weights IS NULL OR array_length(vals, 1) IS NULL THEN
        RETURN array_fill(0.0, ARRAY[array_length(quantiles, 1)]);
    END IF;
    
    n := array_length(vals, 1);
    IF n = 0 THEN
        RETURN array_fill(0.0, ARRAY[array_length(quantiles, 1)]);
    END IF;
    
    -- Calculate total weight more efficiently
    SELECT SUM(w) INTO total_weight
    FROM unnest(weights) w
    WHERE w > 0;
    
    -- Create and sort value-weight pairs in one operation
    sorted_data := ARRAY(
        SELECT ARRAY[v, w]
        FROM unnest(vals, weights) AS t(v, w)
        WHERE w > 0
        ORDER BY v
    );
    
    -- Handle sparse data: add zero if needed
    IF total_weight < 1.0 THEN
        zero_weight := 1.0 - total_weight;
        -- Insert zero at the correct position
        IF sorted_data[1][1] > 0 THEN
            sorted_data := ARRAY[ARRAY[0.0, zero_weight]] || sorted_data;
        ELSE
            sorted_data := sorted_data || ARRAY[ARRAY[0.0, zero_weight]];
        END IF;
        total_weight := 1.0;
    END IF;
    
    n := array_length(sorted_data, 1);
    
    -- Calculate quantiles
    FOR i IN 1..array_length(quantiles, 1) LOOP
        q := quantiles[i];
        target_weight := q * total_weight;
        
        -- Handle edge cases
        IF q <= 0 OR target_weight <= sorted_data[1][2] THEN
            result := array_append(result, sorted_data[1][1]);
        ELSIF q >= 1 THEN
            result := array_append(result, sorted_data[n][1]);
        ELSE
            -- Find position using binary-like search through cumulative weights
            cumsum := 0.0;
            FOR j IN 1..n LOOP
                lower_cum := cumsum;
                cumsum := cumsum + sorted_data[j][2];
                
                IF cumsum >= target_weight THEN
                    IF j = 1 OR cumsum = target_weight THEN
                        result := array_append(result, sorted_data[j][1]);
                    ELSE
                        -- Linear interpolation
                        lower_val := sorted_data[j-1][1];
                        upper_val := sorted_data[j][1];
                        interp_factor := (target_weight - lower_cum) / sorted_data[j][2];
                        result := array_append(result, lower_val + interp_factor * (upper_val - lower_val));
                    END IF;
                    EXIT;
                END IF;
            END LOOP;
        END IF;
    END LOOP;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE;