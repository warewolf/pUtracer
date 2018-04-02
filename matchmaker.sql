SELECT 
  hunt.reference_serial as reference_tube, hunt.match_serial as matching_tube,
round(hunt.delta_ia+hunt.delta_is+hunt.delta_ra+hunt.delta_rs+hunt.delta_gma+hunt.delta_gms+hunt.delta_mua+hunt.delta_mus) AS score,
  hunt.'ref_ia' as 'ref_ia', hunt.'match_ia' as 'match_ia',
  hunt.'ref_is' as 'ref_is', hunt.'match_is' as 'match_is',
  hunt.'ref_ra' as 'ref_ra', hunt.'match_ra' as 'match_ra',
  hunt.'ref_rs' as 'ref_rs', hunt.'match_rs' as 'match_rs',
  hunt.'ref_gma' as 'ref_gma', hunt.'match_gma' as 'match_gma',
  hunt.'ref_gms' as 'ref_gms', hunt.'match_gms' as 'match_gms',
  hunt.'ref_mua' as 'ref_mua', hunt.'match_mua' as 'match_mua', 
  hunt.'ref_mus' as 'ref_mus', hunt.'match_mus' as 'match_mus'
FROM (
  SELECT
    ref.'serial' as reference_serial,
    match.'serial' as match_serial,
    ABS(match.'ia'-ref.'ia') * ABS(match.'ia'-ref.'ia') AS delta_ia,
    ABS(match.'is'-ref.'is') * ABS(match.'is'-ref.'is') AS delta_is,
    ABS(match.'ra'-ref.'ra') * ABS(match.'ra'-ref.'ra') AS delta_ra,
    ABS(match.'rs'-ref.'rs') * ABS(match.'rs'-ref.'rs') AS delta_rs,
    ABS(match.'gma'-ref.'gma') * ABS(match.'gma'-ref.'gma') AS delta_gma,
    ABS(match.'gms'-ref.'gms') * ABS(match.'gms'-ref.'gms') AS delta_gms,
    ABS(match.'mua'-ref.'mua') * ABS(match.'mua'-ref.'mua') AS delta_mua,
    ABS(match.'mus'-ref.'mus') * ABS(match.'mus'-ref.'mus') AS delta_mus,
    ref.'ia' as ref_ia,
    ref.'is' as ref_is,
    ref.'ra' as ref_ra,
    ref.'rs' as ref_rs,
    ref.'gma' as ref_gma,
    ref.'gms' as ref_gms,
    ref.'mua' as ref_mua,
    ref.'mus' as ref_mus,
    match.'ia' as match_ia,
    match.'is' as match_is,
    match.'ra' as match_ra,
    match.'rs' as match_rs,
    match.'gma' as match_gma,
    match.'gms' as match_gms,
    match.'mua' as match_mua,
    match.'mus' as match_mus
  FROM
    tubes ref, tubes match
  WHERE
    ref.'type' = match.'type'
) AS hunt
WHERE score < 10 AND reference_tube != matching_tube
ORDER BY reference_tube ASC, score ASC;
