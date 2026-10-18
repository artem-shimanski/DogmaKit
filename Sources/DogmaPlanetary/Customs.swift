//
//  Customs.swift
//  DogmaPlanetary
//
//  Created by Artem Shimanski on 14.10.2026.
//

/// Customs office (POCO) duties and command center launch cost.
///
/// Separate from the production graph: the simulation does not touch them. The base is a fixed unit price per tier
/// (the SDE has none: `basePrice` of PI commodities is a 1.0 placeholder); values and multipliers follow
/// the EVE University wiki **[unverified]**:
/// - export = base x quantity x rate;
/// - import = half of export;
/// - launch from a command center = export x 1.5.
///
/// The rate is the final customs rate (owner tax + NPC part - Customs Code Expertise); only the consumer knows it.
public enum Customs {

    /// Unit price used to compute the duty, ISK.
    public static func baseValue(of tier: DogmaPlanetaryData.Tier) -> Double {
        switch tier {
        case .p0: 5
        case .p1: 400
        case .p2: 7_200
        case .p3: 60_000
        case .p4: 1_200_000
        }
    }

    /// Customs export duty. Commodities unknown to the catalog are not charged.
    public static func exportFee(for goods: Inventory, taxRate: Double, catalog: PlanetaryCatalog) -> Double {
        goods.reduce(0) { sum, item in
            guard let tier = catalog.commodity(item.typeID)?.tier else { return sum }
            return sum + baseValue(of: tier) * Double(item.quantity) * taxRate
        }
    }

    /// Customs import duty: half of the export duty.
    public static func importFee(for goods: Inventory, taxRate: Double, catalog: PlanetaryCatalog) -> Double {
        exportFee(for: goods, taxRate: taxRate, catalog: catalog) / 2
    }

    /// Cost of launching cargo from a command center to orbit: the export duty x 1.5.
    public static func commandCenterLaunchFee(for goods: Inventory, taxRate: Double, catalog: PlanetaryCatalog) -> Double {
        exportFee(for: goods, taxRate: taxRate, catalog: catalog) * 1.5
    }
}
