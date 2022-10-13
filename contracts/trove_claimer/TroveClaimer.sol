//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {TroveClaimerAdmin, Initializable, ClaimInfo, ITroveBadges} from "./TroveClaimerAdmin.sol";
import {ECDSAUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/draft-EIP712Upgradeable.sol";

contract TroveClaimer is Initializable, EIP712Upgradeable, TroveClaimerAdmin {

    function initialize(address _validator, address _badgeAddress) external initializer {
        __TroveClaimerAdmin_init();
        validator = _validator;
        troveBadgeCollection = ITroveBadges(_badgeAddress);
    }

    function claim(
        ClaimInfo calldata _claimInfo,
        bytes memory _validatorSignature
    )
        external
        override
        whenNotPaused
    {
        if(_claimInfo.claimer != msg.sender) {
            revert NotRecipient();
        }
        if(!_isSupportedBadge(_claimInfo.badgeAddress, _claimInfo.badgeId)) {
            // For now, only support TroveBadges
            revert InvalidBadge(_claimInfo.badgeAddress, _claimInfo.badgeId);
        }
        bytes32 claimToHash = claimInfoHash(_claimInfo);
        address signer = ECDSAUpgradeable.recover(claimToHash, _validatorSignature);
        if(signer != validator) {
            revert InvalidSignature(signer);
        }
        if(troveBadgeCollection.balanceOf(_claimInfo.claimer, _claimInfo.badgeId) > 0) {
            revert BadgeAlreadyClaimed(_claimInfo.claimer, _claimInfo.badgeAddress, _claimInfo.badgeId);
        }
        troveBadgeCollection.adminMint(msg.sender, _claimInfo.badgeId);
        // todo: mint utility associated to the given collection address + badgeId
    }

    function _isSupportedBadge(address _badgeAddress, uint256 _badgeId) internal view returns (bool isSupported_) {
        isSupported_ = badgeToEnabledStatus[_badgeAddress][_badgeId];
    }

    function claimInfoHash(ClaimInfo calldata _claimInfo) public view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        CLAIMINFO_TYPE_HASH,
                        _claimInfo.claimer,
                        _claimInfo.badgeAddress,
                        _claimInfo.badgeId
                    )
                )
            );
    }
}