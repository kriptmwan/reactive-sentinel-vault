// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Mock price oracle for the Sentinel Vault demo.
/// @notice Emits the events the Reactive sentinel subscribes to. THIS IS A MOCK: the price is
///         set by the owner (the demo operator) instead of coming from a real feed, so the
///         demo can drive a breach and a recovery on demand. A production oracle would be a
///         Chainlink feed or equivalent; the sentinel logic is feed-agnostic.
/// @dev Prices are USD per 1 mVOL with 18 decimals (e.g. 2000e18 = $2,000).
///      Timestamps are the ORIGIN block timestamp, carried in the event payload — the
///      sentinel must never use Lasna block numbers/timestamps as a substitute.
contract PriceOracle is Ownable {
    /// @notice Emitted on every price update. Non-indexed payload: (price, timestamp).
    event PriceUpdated(uint256 price, uint256 timestamp);

    /// @notice Emitted when the price recovers to `threshold + 5%` after a breach.
    ///         Non-indexed payload: (price, timestamp).
    event PriceRecovered(uint256 price, uint256 timestamp);

    /// @notice Emitted when the threshold changes. Non-indexed payload: (threshold, timestamp).
    event ThresholdUpdated(uint256 threshold, uint256 timestamp);

    /// @notice Current price (USD per mVOL, 18 decimals).
    uint256 public price;

    /// @notice Breach threshold (USD per mVOL, 18 decimals). Exit fires below this.
    uint256 public threshold;

    /// @notice True while the last observed price is below `threshold`.
    bool public belowThreshold;

    /// @param threshold_ Initial breach threshold (18 decimals).
    /// @param initialPrice_ Initial price (18 decimals).
    constructor(uint256 threshold_, uint256 initialPrice_) Ownable(msg.sender) {
        require(threshold_ > 0, "PriceOracle: threshold is zero");
        require(initialPrice_ > 0, "PriceOracle: price is zero");
        threshold = threshold_;
        price = initialPrice_;
        belowThreshold = initialPrice_ < threshold_;
    }

    /// @notice Recovery price: threshold + 5%. Re-arm fires at or above this.
    function recoveryPrice() public view returns (uint256) {
        return (threshold * 105) / 100;
    }

    /// @notice Updates the threshold. Owner only.
    function setThreshold(uint256 threshold_) external onlyOwner {
        require(threshold_ > 0, "PriceOracle: threshold is zero");
        threshold = threshold_;
        emit ThresholdUpdated(threshold_, block.timestamp);
    }

    /// @notice Publishes a new price. Owner only (demo operator).
    /// @dev Always emits PriceUpdated. Emits PriceRecovered exactly on the crossing from
    ///      below-threshold back to at-or-above recoveryPrice, so the sentinel can re-arm.
    function setPrice(uint256 newPrice_) external onlyOwner {
        require(newPrice_ > 0, "PriceOracle: price is zero");
        price = newPrice_;
        emit PriceUpdated(newPrice_, block.timestamp);
        if (belowThreshold && newPrice_ >= recoveryPrice()) {
            belowThreshold = false;
            emit PriceRecovered(newPrice_, block.timestamp);
        } else if (!belowThreshold && newPrice_ < threshold) {
            belowThreshold = true;
        }
    }
}
