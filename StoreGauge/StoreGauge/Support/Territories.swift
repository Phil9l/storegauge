//
//  Territories.swift
//  StoreGauge
//
//  Maps App Store 3-letter territory codes to ISO 3166-1 alpha-2 (for flag emoji).
//  Not exhaustive; unknown codes fall back to the first two letters.
//

let territoryToISO2: [String: String] = [
    "USA": "US", "GBR": "GB", "CAN": "CA", "AUS": "AU", "DEU": "DE", "FRA": "FR",
    "ITA": "IT", "ESP": "ES", "NLD": "NL", "SWE": "SE", "NOR": "NO", "DNK": "DK",
    "FIN": "FI", "IRL": "IE", "BEL": "BE", "AUT": "AT", "CHE": "CH", "PRT": "PT",
    "POL": "PL", "CZE": "CZ", "GRC": "GR", "HUN": "HU", "ROU": "RO", "RUS": "RU",
    "UKR": "UA", "TUR": "TR", "ISR": "IL", "SAU": "SA", "ARE": "AE", "EGY": "EG",
    "ZAF": "ZA", "NGA": "NG", "KEN": "KE", "JPN": "JP", "CHN": "CN", "KOR": "KR",
    "TWN": "TW", "HKG": "HK", "SGP": "SG", "MYS": "MY", "THA": "TH", "IDN": "ID",
    "PHL": "PH", "VNM": "VN", "IND": "IN", "PAK": "PK", "BGD": "BD", "LKA": "LK",
    "NZL": "NZ", "MEX": "MX", "BRA": "BR", "ARG": "AR", "CHL": "CL", "COL": "CO",
    "PER": "PE", "ECU": "EC", "VEN": "VE", "URY": "UY", "BOL": "BO", "CRI": "CR",
    "PAN": "PA", "GTM": "GT", "DOM": "DO", "HRV": "HR", "SVK": "SK", "SVN": "SI",
    "BGR": "BG", "LTU": "LT", "LVA": "LV", "EST": "EE", "SRB": "RS", "ISL": "IS",
    "LUX": "LU", "MLT": "MT", "CYP": "CY", "QAT": "QA", "KWT": "KW", "BHR": "BH",
    "OMN": "OM", "JOR": "JO", "LBN": "LB", "MAR": "MA", "DZA": "DZ", "TUN": "TN",
    "KAZ": "KZ", "GEO": "GE", "ARM": "AM", "AZE": "AZ", "BLR": "BY", "MDA": "MD",
    "ALB": "AL", "MKD": "MK", "BIH": "BA", "MNE": "ME", "GHA": "GH", "TZA": "TZ",
    "UGA": "UG", "ZWE": "ZW", "MOZ": "MZ", "AGO": "AO", "CMR": "CM", "CIV": "CI",
    "SEN": "SN", "NPL": "NP", "KHM": "KH", "LAO": "LA", "MMR": "MM", "MNG": "MN",
    "BRN": "BN", "MAC": "MO", "FJI": "FJ", "PNG": "PG", "PRY": "PY", "HND": "HN",
    "NIC": "NI", "SLV": "SV", "JAM": "JM", "TTO": "TT", "BRB": "BB", "BHS": "BS",
]
