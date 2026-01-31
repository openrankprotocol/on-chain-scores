// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {WalletScoreTestBase} from "./WalletScoreTestBase.sol";
import {IWalletScore} from "src/WalletScore/IWalletScore.sol";
import {PublisherId, Publisher} from "src/WalletScore/Types.sol";

contract PublisherTest is WalletScoreTestBase {
    // ============ Registration Tests ============

    function test_registerPublisher_Success() public {
        _registerPublisher1();

        Publisher memory pub = ws.getPublisher(publisher1Id);
        assertEq(pub.currentAddress, publisher1Addr);
        assertEq(pub.metadataUri, PUBLISHER_METADATA);
        assertTrue(pub.active);
        assertEq(pub.denylistUntil, 0);
    }

    function test_registerPublisher_AssignsIncrementingIds() public {
        _registerAllPublishers();

        assertEq(PublisherId.unwrap(publisher1Id), 1);
        assertEq(PublisherId.unwrap(publisher2Id), 2);
        assertEq(PublisherId.unwrap(publisher3Id), 3);
    }

    function test_registerPublisher_EmitsPublisherRegistered() public {
        vm.expectEmit(true, true, false, true);
        emit IWalletScore.PublisherRegistered(PublisherId.wrap(1), publisher1Addr, PUBLISHER_METADATA);

        vm.prank(admin);
        ws.registerPublisher(publisher1Addr, PUBLISHER_METADATA);
    }

    function test_registerPublisher_GrantsPublisherRole() public {
        _registerPublisher1();

        assertTrue(ws.hasRole(ws.PUBLISHER_ROLE(), publisher1Addr));
    }

    function test_registerPublisher_RevertWhenNotAdmin() public {
        vm.prank(nobody);
        vm.expectRevert();
        ws.registerPublisher(publisher1Addr, PUBLISHER_METADATA);
    }

    function test_registerPublisher_RevertWhenAddressAlreadyRegistered() public {
        _registerPublisher1();

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IWalletScore.PublisherAddressAlreadyRegistered.selector, publisher1Addr)
        );
        ws.registerPublisher(publisher1Addr, "different-metadata");
    }

    // ============ Address Update Tests ============

    function test_updatePublisherAddress_ByOwner() public {
        _registerPublisher1();

        address newAddr = makeAddr("newPublisher1Addr");

        vm.prank(publisher1Addr);
        ws.updatePublisherAddress(publisher1Id, newAddr);

        Publisher memory pub = ws.getPublisher(publisher1Id);
        assertEq(pub.currentAddress, newAddr);
    }

    function test_updatePublisherAddress_ByAdmin() public {
        _registerPublisher1();

        address newAddr = makeAddr("newPublisher1Addr");

        vm.prank(admin);
        ws.updatePublisherAddress(publisher1Id, newAddr);

        Publisher memory pub = ws.getPublisher(publisher1Id);
        assertEq(pub.currentAddress, newAddr);
    }

    function test_updatePublisherAddress_UpdatesReverseLookup() public {
        _registerPublisher1();

        address newAddr = makeAddr("newPublisher1Addr");

        vm.prank(publisher1Addr);
        ws.updatePublisherAddress(publisher1Id, newAddr);

        (PublisherId foundId,) = ws.getPublisherByAddress(newAddr);
        assertEq(PublisherId.unwrap(foundId), PublisherId.unwrap(publisher1Id));

        vm.expectRevert();
        ws.getPublisherByAddress(publisher1Addr);
    }

    function test_updatePublisherAddress_TransfersRole() public {
        _registerPublisher1();

        address newAddr = makeAddr("newPublisher1Addr");

        vm.prank(publisher1Addr);
        ws.updatePublisherAddress(publisher1Id, newAddr);

        assertFalse(ws.hasRole(ws.PUBLISHER_ROLE(), publisher1Addr));
        assertTrue(ws.hasRole(ws.PUBLISHER_ROLE(), newAddr));
    }

    function test_updatePublisherAddress_EmitsPublisherAddressUpdated() public {
        _registerPublisher1();

        address newAddr = makeAddr("newPublisher1Addr");

        vm.expectEmit(true, true, true, false);
        emit IWalletScore.PublisherAddressUpdated(publisher1Id, publisher1Addr, newAddr);

        vm.prank(publisher1Addr);
        ws.updatePublisherAddress(publisher1Id, newAddr);
    }

    function test_updatePublisherAddress_RevertWhenNotOwnerOrAdmin() public {
        _registerPublisher1();

        address newAddr = makeAddr("newAddr");

        vm.prank(nobody);
        vm.expectRevert(abi.encodeWithSelector(IWalletScore.NotPublisherOrAdmin.selector, publisher1Id));
        ws.updatePublisherAddress(publisher1Id, newAddr);
    }

    function test_updatePublisherAddress_RevertWhenNewAddressAlreadyRegistered() public {
        _registerPublisher1();
        _registerPublisher2();

        vm.prank(publisher1Addr);
        vm.expectRevert(
            abi.encodeWithSelector(IWalletScore.PublisherAddressAlreadyRegistered.selector, publisher2Addr)
        );
        ws.updatePublisherAddress(publisher1Id, publisher2Addr);
    }

    // ============ Metadata Update Tests ============

    function test_updatePublisherMetadata_ByOwner() public {
        _registerPublisher1();

        string memory newMetadata = "ipfs://new-publisher-metadata";

        vm.prank(publisher1Addr);
        ws.updatePublisherMetadata(publisher1Id, newMetadata);

        Publisher memory pub = ws.getPublisher(publisher1Id);
        assertEq(pub.metadataUri, newMetadata);
    }

    function test_updatePublisherMetadata_ByAdmin() public {
        _registerPublisher1();

        string memory newMetadata = "ipfs://new-publisher-metadata";

        vm.prank(admin);
        ws.updatePublisherMetadata(publisher1Id, newMetadata);

        Publisher memory pub = ws.getPublisher(publisher1Id);
        assertEq(pub.metadataUri, newMetadata);
    }

    function test_updatePublisherMetadata_EmitsPublisherMetadataUpdated() public {
        _registerPublisher1();

        string memory newMetadata = "ipfs://new-publisher-metadata";

        vm.expectEmit(true, false, false, true);
        emit IWalletScore.PublisherMetadataUpdated(publisher1Id, newMetadata);

        vm.prank(publisher1Addr);
        ws.updatePublisherMetadata(publisher1Id, newMetadata);
    }

    function test_updatePublisherMetadata_RevertWhenNotOwnerOrAdmin() public {
        _registerPublisher1();

        vm.prank(nobody);
        vm.expectRevert(abi.encodeWithSelector(IWalletScore.NotPublisherOrAdmin.selector, publisher1Id));
        ws.updatePublisherMetadata(publisher1Id, "new-metadata");
    }

    // ============ Deactivation Tests ============

    function test_deactivatePublisher_Success() public {
        _registerPublisher1();

        vm.prank(admin);
        ws.deactivatePublisher(publisher1Id);

        Publisher memory pub = ws.getPublisher(publisher1Id);
        assertFalse(pub.active);
    }

    function test_deactivatePublisher_RevokesRole() public {
        _registerPublisher1();

        vm.prank(admin);
        ws.deactivatePublisher(publisher1Id);

        assertFalse(ws.hasRole(ws.PUBLISHER_ROLE(), publisher1Addr));
    }

    function test_deactivatePublisher_EmitsPublisherDeactivated() public {
        _registerPublisher1();

        vm.expectEmit(true, false, false, false);
        emit IWalletScore.PublisherDeactivated(publisher1Id);

        vm.prank(admin);
        ws.deactivatePublisher(publisher1Id);
    }

    function test_deactivatePublisher_RevertWhenNotAdmin() public {
        _registerPublisher1();

        vm.prank(publisher1Addr);
        vm.expectRevert();
        ws.deactivatePublisher(publisher1Id);
    }

    // ============ Bond Deposit Tests ============

    function test_depositBond_Success() public {
        _registerPublisher1();
        vm.deal(publisher1Addr, 1 ether);

        vm.prank(publisher1Addr);
        ws.depositBond{value: 1 ether}();

        assertEq(ws.getPublisherBond(publisher1Id), 1 ether);
    }

    function test_depositBond_AccumulatesMultipleDeposits() public {
        _registerPublisher1();
        vm.deal(publisher1Addr, 3 ether);

        vm.startPrank(publisher1Addr);
        ws.depositBond{value: 1 ether}();
        ws.depositBond{value: 0.5 ether}();
        ws.depositBond{value: 1.5 ether}();
        vm.stopPrank();

        assertEq(ws.getPublisherBond(publisher1Id), 3 ether);
    }

    function test_depositBond_EmitsBondDeposited() public {
        _registerPublisher1();
        vm.deal(publisher1Addr, 1 ether);

        vm.expectEmit(true, false, false, true);
        emit IWalletScore.BondDeposited(publisher1Id, 1 ether, 1 ether);

        vm.prank(publisher1Addr);
        ws.depositBond{value: 1 ether}();
    }

    function test_depositBond_RevertWhenNotRegistered() public {
        vm.deal(nobody, 1 ether);

        vm.prank(nobody);
        vm.expectRevert(abi.encodeWithSelector(IWalletScore.PublisherNotFound.selector, PublisherId.wrap(0)));
        ws.depositBond{value: 1 ether}();
    }

    function test_depositBond_RevertWhenDeactivated() public {
        _registerPublisher1();
        vm.deal(publisher1Addr, 1 ether);

        vm.prank(admin);
        ws.deactivatePublisher(publisher1Id);

        vm.prank(publisher1Addr);
        vm.expectRevert(abi.encodeWithSelector(IWalletScore.PublisherNotActive.selector, publisher1Id));
        ws.depositBond{value: 1 ether}();
    }

    // ============ Bond Withdrawal Tests ============

    function test_withdrawBond_FullWithdrawal() public {
        _registerAndFundPublisher1();

        uint256 balanceBefore = publisher1Addr.balance;

        vm.prank(publisher1Addr);
        ws.withdrawBond(DEFAULT_BOND);

        assertEq(ws.getPublisherBond(publisher1Id), 0);
        assertEq(publisher1Addr.balance, balanceBefore + DEFAULT_BOND);
    }

    function test_withdrawBond_PartialWithdrawal() public {
        _registerPublisher1();
        _fundAndDepositBondForPublisher1(2 ether);

        vm.prank(publisher1Addr);
        ws.withdrawBond(1 ether);

        assertEq(ws.getPublisherBond(publisher1Id), 1 ether);
    }

    function test_withdrawBond_EmitsBondWithdrawn() public {
        _registerAndFundPublisher1();

        vm.expectEmit(true, false, false, true);
        emit IWalletScore.BondWithdrawn(publisher1Id, DEFAULT_BOND, 0);

        vm.prank(publisher1Addr);
        ws.withdrawBond(DEFAULT_BOND);
    }

    function test_withdrawBond_RevertWhenInsufficientBalance() public {
        _registerAndFundPublisher1();

        vm.prank(publisher1Addr);
        vm.expectRevert(
            abi.encodeWithSelector(IWalletScore.InsufficientBondBalance.selector, 2 ether, DEFAULT_BOND)
        );
        ws.withdrawBond(2 ether);
    }

    function test_withdrawBond_RevertWhenBelowMinimum() public {
        _registerPublisher1();
        _fundAndDepositBondForPublisher1(0.5 ether);

        vm.prank(publisher1Addr);
        vm.expectRevert(
            abi.encodeWithSelector(IWalletScore.BondBelowMinimum.selector, 0.05 ether, MIN_BOND)
        );
        ws.withdrawBond(0.45 ether);
    }

    function test_withdrawBond_AllowsFullWithdrawalEvenBelowMinimum() public {
        _registerAndFundPublisher1();

        vm.prank(publisher1Addr);
        ws.withdrawBond(DEFAULT_BOND);

        assertEq(ws.getPublisherBond(publisher1Id), 0);
    }

    // ============ Query Tests ============

    function test_getPublisher_RevertWhenNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(IWalletScore.PublisherNotFound.selector, PublisherId.wrap(999)));
        ws.getPublisher(PublisherId.wrap(999));
    }

    function test_getPublisherByAddress_Success() public {
        _registerPublisher1();

        (PublisherId foundId, Publisher memory pub) = ws.getPublisherByAddress(publisher1Addr);

        assertEq(PublisherId.unwrap(foundId), PublisherId.unwrap(publisher1Id));
        assertEq(pub.currentAddress, publisher1Addr);
    }

    function test_getPublisherByAddress_RevertWhenNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(IWalletScore.PublisherNotFound.selector, PublisherId.wrap(0)));
        ws.getPublisherByAddress(nobody);
    }

    // ============ Min Bond Configuration Tests ============

    function test_setMinPublisherBond_Success() public {
        vm.prank(admin);
        ws.setMinPublisherBond(0.5 ether);

        assertEq(ws.getMinPublisherBond(), 0.5 ether);
    }

    function test_setMinPublisherBond_RevertWhenNotAdmin() public {
        vm.prank(nobody);
        vm.expectRevert();
        ws.setMinPublisherBond(0.5 ether);
    }

    // ============ Denylist Params Tests ============

    function test_setDenylistParams_Success() public {
        vm.prank(admin);
        ws.setDenylistParams(2 days, 2 hours, 2 ether);

        (uint256 base, uint256 perLost, uint256 divisor) = ws.getDenylistParams();
        assertEq(base, 2 days);
        assertEq(perLost, 2 hours);
        assertEq(divisor, 2 ether);
    }

    function test_setDenylistParams_RevertWhenNotAdmin() public {
        vm.prank(nobody);
        vm.expectRevert();
        ws.setDenylistParams(2 days, 2 hours, 2 ether);
    }
}
