/**
 * Risk Label Taxonomy — single source of truth giữa Backend và Frontend.
 *
 * Khi FE M3/M4 cần hiển thị UI buttons, họ phải import danh sách subtype
 * y hệt ở đây để FE và BE đồng bộ. Nếu thêm subtype mới, sửa file này.
 *
 * Triết lý:
 *   - Category = nhóm icon to ở màn hình chính (chỉ 5 cái, leader liếc thấy ngay)
 *   - Subtype = lựa chọn cụ thể sau khi mở category (3-4 nút nhỏ)
 *   - Mỗi subtype có time decay riêng (chốt CSGT tan nhanh, ổ gà tồn lâu)
 */

export type RiskCategory =
  | 'WEATHER'
  | 'ACCIDENT'
  | 'ROAD_BAD'
  | 'POLICE'
  | 'HAZARD_OTHER';

export interface SubtypeConfig {
  subtype: string;
  vi: string;
  /** Linear time decay: severity = base * max(0, 1 - hoursPassed/maxLifetimeH) */
  halfLifeH: number;
  maxLifetimeH: number;
  /** Severity mặc định nếu leader không chỉ định */
  defaultSeverity: number;
}

export const RISK_TAXONOMY: Record<RiskCategory, {
  vi: string;
  icon: string;
  subtypes: SubtypeConfig[];
}> = {
  WEATHER: {
    vi: 'Thời tiết xấu',
    icon: '☔',
    subtypes: [
      { subtype: 'heavy_rain', vi: 'Mưa to', halfLifeH: 1, maxLifetimeH: 2, defaultSeverity: 0.6 },
      { subtype: 'fog', vi: 'Sương mù', halfLifeH: 1, maxLifetimeH: 2, defaultSeverity: 0.7 },
      { subtype: 'strong_wind', vi: 'Gió lớn', halfLifeH: 1, maxLifetimeH: 2, defaultSeverity: 0.5 },
      { subtype: 'flooding', vi: 'Ngập nước', halfLifeH: 2, maxLifetimeH: 6, defaultSeverity: 0.8 },
    ],
  },
  ACCIDENT: {
    vi: 'Tai nạn / Tắc đường',
    icon: '⚠️',
    subtypes: [
      { subtype: 'accident', vi: 'Tai nạn', halfLifeH: 4, maxLifetimeH: 12, defaultSeverity: 0.9 },
      { subtype: 'traffic_jam', vi: 'Tắc đường', halfLifeH: 2, maxLifetimeH: 6, defaultSeverity: 0.5 },
      { subtype: 'breakdown', vi: 'Xe hỏng/chết máy', halfLifeH: 3, maxLifetimeH: 8, defaultSeverity: 0.6 },
    ],
  },
  ROAD_BAD: {
    vi: 'Đường xấu',
    icon: '🕳️',
    subtypes: [
      { subtype: 'pothole', vi: 'Ổ gà', halfLifeH: 168, maxLifetimeH: 720, defaultSeverity: 0.5 }, // 7d, 30d
      { subtype: 'slippery', vi: 'Đường trơn', halfLifeH: 4, maxLifetimeH: 12, defaultSeverity: 0.7 },
      { subtype: 'gravel', vi: 'Sỏi đá', halfLifeH: 48, maxLifetimeH: 168, defaultSeverity: 0.5 },
      { subtype: 'construction', vi: 'Đang thi công', halfLifeH: 48, maxLifetimeH: 240, defaultSeverity: 0.6 }, // 10d
    ],
  },
  POLICE: {
    vi: 'Chốt / Camera CSGT',
    icon: '🚓',
    subtypes: [
      { subtype: 'checkpoint', vi: 'Chốt CSGT', halfLifeH: 3, maxLifetimeH: 6, defaultSeverity: 0.7 },
      { subtype: 'speed_camera', vi: 'Camera tốc độ', halfLifeH: 168, maxLifetimeH: 720, defaultSeverity: 0.5 }, // 7d, 30d (cố định)
      { subtype: 'mobile_patrol', vi: 'Tuần tra di động', halfLifeH: 1, maxLifetimeH: 3, defaultSeverity: 0.7 },
    ],
  },
  HAZARD_OTHER: {
    vi: 'Nguy hiểm khác',
    icon: '🚧',
    subtypes: [
      { subtype: 'landslide', vi: 'Sạt lở', halfLifeH: 12, maxLifetimeH: 48, defaultSeverity: 1.0 },
      { subtype: 'fallen_tree', vi: 'Cây đổ', halfLifeH: 6, maxLifetimeH: 24, defaultSeverity: 0.8 },
      { subtype: 'animal', vi: 'Động vật băng đường', halfLifeH: 2, maxLifetimeH: 6, defaultSeverity: 0.5 },
      { subtype: 'dark_road', vi: 'Đường tối nguy hiểm', halfLifeH: 24, maxLifetimeH: 168, defaultSeverity: 0.4 },
    ],
  },
};

/** Tổng hợp tất cả subtype để FE/BE validate nhanh. */
export const ALL_SUBTYPES: Array<{
  category: RiskCategory;
  subtype: string;
  vi: string;
}> = Object.entries(RISK_TAXONOMY).flatMap(([cat, info]) =>
  info.subtypes.map((s) => ({
    category: cat as RiskCategory,
    subtype: s.subtype,
    vi: s.vi,
  }))
);

/**
 * Lookup nhanh subtype config theo (category, subtype).
 * Trả null nếu cặp không hợp lệ.
 */
export function findSubtypeConfig(
  category: string,
  subtype: string
): { category: RiskCategory; config: SubtypeConfig } | null {
  if (!(category in RISK_TAXONOMY)) return null;
  const cat = category as RiskCategory;
  const config = RISK_TAXONOMY[cat].subtypes.find((s) => s.subtype === subtype);
  return config ? { category: cat, config } : null;
}

/**
 * Linear time decay theo subtype config.
 * Return giá trị 0..1 (sau khi nhân với baseSeverity).
 */
export function computeEffectiveSeverity(
  baseSeverity: number,
  subtypeConfig: SubtypeConfig,
  createdAtMs: number,
  nowMs: number
): number {
  const hoursPassed = (nowMs - createdAtMs) / (3600 * 1000);
  if (hoursPassed >= subtypeConfig.maxLifetimeH) return 0;
  const factor = Math.max(0, 1 - hoursPassed / subtypeConfig.maxLifetimeH);
  return Math.max(0, Math.min(1, baseSeverity * factor));
}
