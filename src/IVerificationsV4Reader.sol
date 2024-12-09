// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

/// @notice ETH address <> FID contract interface
/// @author Neynar
/// Taken from https://docs.neynar.com/docs/verifications-contract.
interface IVerificationsV4Reader {
    /// @notice Map a verifier address into FID, 0 means no verification for the address.
    function getFid(address verifier) external view returns (uint256 fid);

    /// @notice Same as `getFid` but emits an event so Neynar knows usage.
    function getFidWithEvent(address verifier) external returns (uint256 fid);

    /// @notice A batch version of `getFid`.
    function getFids(address[] calldata verifiers) external view returns (uint256[] memory fid);
}
