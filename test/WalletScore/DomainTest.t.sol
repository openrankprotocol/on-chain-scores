// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {WalletScoreTestBase} from "./WalletScoreTestBase.sol";
import {IWalletScore} from "src/WalletScore/IWalletScore.sol";
import {DomainId} from "src/WalletScore/Types.sol";

contract DomainTest is WalletScoreTestBase {
    // ============ Registration Tests ============

    function test_registerDomain_Success() public {
        vm.prank(admin);
        ws.registerDomain(domainAvici, DOMAIN_METADATA);

        string memory metadata = ws.getDomainMetadataUri(domainAvici);
        assertEq(metadata, DOMAIN_METADATA);
    }

    function test_registerDomain_EmitsDomainRegistered() public {
        vm.expectEmit(true, false, false, true);
        emit IWalletScore.DomainRegistered(domainAvici, DOMAIN_METADATA);

        vm.prank(admin);
        ws.registerDomain(domainAvici, DOMAIN_METADATA);
    }

    function test_registerDomain_RevertWhenNotAdmin() public {
        vm.prank(nobody);
        vm.expectRevert();
        ws.registerDomain(domainAvici, DOMAIN_METADATA);
        vm.prank(publisher1Addr);
        vm.expectRevert();
        ws.registerDomain(domainAvici, DOMAIN_METADATA);
    }

    function test_registerDomain_RejectEmptyMetadata() public {
        vm.prank(admin);
        vm.expectRevert();
        ws.registerDomain(domainAvici, "");
    }

    function test_registerDomain_RevertWhenAlreadyExists() public {
        _registerDomainAvici();

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IWalletScore.DomainAlreadyExists.selector, domainAvici));
        ws.registerDomain(domainAvici, "different-metadata");
    }

    function test_registerDomain_MultipleDomains() public {
        _registerBothDomains();

        assertEq(ws.getDomainMetadataUri(domainAvici), DOMAIN_METADATA);
        assertEq(ws.getDomainMetadataUri(domainUniswap), DOMAIN_METADATA);
    }

    // ============ Metadata Update Tests ============

    function test_updateDomainMetadata_Success() public {
        _registerDomainAvici();

        string memory newMetadata = "ipfs://updated-metadata";
        vm.prank(admin);
        ws.updateDomainMetadata(domainAvici, newMetadata);

        assertEq(ws.getDomainMetadataUri(domainAvici), newMetadata);
    }

    function test_updateDomainMetadata_EmitsDomainMetadataUpdated() public {
        _registerDomainAvici();

        string memory newMetadata = "ipfs://updated-metadata";

        vm.expectEmit(true, false, false, true);
        emit IWalletScore.DomainMetadataUpdated(domainAvici, newMetadata);

        vm.prank(admin);
        ws.updateDomainMetadata(domainAvici, newMetadata);
    }

    function test_updateDomainMetadata_RevertWhenNotAdmin() public {
        _registerDomainAvici();

        vm.prank(nobody);
        vm.expectRevert();
        ws.updateDomainMetadata(domainAvici, "new-metadata");
    }

    function test_updateDomainMetadata_RevertWhenDomainNotFound() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IWalletScore.DomainNotFound.selector, domainUnregistered));
        ws.updateDomainMetadata(domainUnregistered, "metadata");
    }

    // ============ Query Tests ============

    function test_getDomainMetadataUri_RevertWhenNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(IWalletScore.DomainNotFound.selector, domainUnregistered));
        ws.getDomainMetadataUri(domainUnregistered);
    }
}
