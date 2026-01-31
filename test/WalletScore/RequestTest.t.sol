// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {WalletScoreTestBase} from "./WalletScoreTestBase.sol";
import {IWalletScore} from "src/WalletScore/IWalletScore.sol";
import {
    DomainId,
    ScoreSetId,
    RequestId,
    BidId,
    BidSelection,
    RequestStatus,
    ScoreRequest,
    Entry
} from "src/WalletScore/Types.sol";

contract RequestTest is WalletScoreTestBase {
    function setUp() public override {
        super.setUp();
        _setupBasicFixture();
    }

    // ============ Creation Tests - Wallet Requests ============

    function test_createRequest_WalletRequest_Success() public {
        uint256 quotingDeadline = block.timestamp + 1 hours;
        uint256 fulfillmentDeadline = block.timestamp + 2 hours;
        uint256 budget = 0.5 ether;

        address[] memory wallets = _singleWalletArray(address(0x1000));

        RequestId id = _createWalletRequest(
            requester1,
            domainAvici,
            wallets,
            block.timestamp - 1 days,
            block.timestamp + 1 days,
            quotingDeadline,
            fulfillmentDeadline,
            budget
        );

        ScoreRequest memory req = ws.getRequest(id);
        assertEq(req.requester, requester1);
        assertEq(DomainId.unwrap(req.domainId), DomainId.unwrap(domainAvici));
        assertEq(req.wallets.length, 1);
        assertEq(req.wallets[0], address(0x1000));
        assertEq(req.startRank, 0);
        assertEq(req.rankCount, 0);
        assertEq(req.quotingDeadline, quotingDeadline);
        assertEq(req.fulfillmentDeadline, fulfillmentDeadline);
        assertEq(req.maxBudget, budget);
        assertEq(uint8(req.selectionMode), uint8(BidSelection.Cheapest));
        assertEq(uint8(req.status), uint8(RequestStatus.Quoting));
    }

    function test_createRequest_EmitsRequestCreated() public {
        uint256 budget = 0.5 ether;
        address[] memory wallets = _singleWalletArray(address(0x1000));

        vm.expectEmit(true, true, true, true);
        emit IWalletScore.RequestCreated(RequestId.wrap(1), requester1, domainAvici, budget);

        _createWalletRequest(
            requester1,
            domainAvici,
            wallets,
            block.timestamp - 1 days,
            block.timestamp + 1 days,
            block.timestamp + 1 hours,
            block.timestamp + 2 hours,
            budget
        );
    }

    function test_createRequest_AssignsIncrementingIds() public {
        address[] memory wallets = _singleWalletArray(address(0x1000));

        RequestId id1 = _createWalletRequest(
            requester1, domainAvici, wallets,
            block.timestamp - 1 days, block.timestamp + 1 days,
            block.timestamp + 1 hours, block.timestamp + 2 hours, 0.1 ether
        );
        RequestId id2 = _createWalletRequest(
            requester1, domainAvici, wallets,
            block.timestamp - 1 days, block.timestamp + 1 days,
            block.timestamp + 1 hours, block.timestamp + 2 hours, 0.1 ether
        );

        assertEq(RequestId.unwrap(id1), 1);
        assertEq(RequestId.unwrap(id2), 2);
    }

    function test_createRequest_MultipleWallets() public {
        address[] memory wallets = _twoWalletArray(address(0x1000), address(0x1001));

        RequestId id = _createWalletRequest(
            requester1, domainAvici, wallets,
            block.timestamp - 1 days, block.timestamp + 1 days,
            block.timestamp + 1 hours, block.timestamp + 2 hours, 0.5 ether
        );

        ScoreRequest memory req = ws.getRequest(id);
        assertEq(req.wallets.length, 2);
        assertEq(req.wallets[0], address(0x1000));
        assertEq(req.wallets[1], address(0x1001));
    }

    // ============ Creation Tests - Rank Range Requests ============

    function test_createRequest_RankRangeRequest_Success() public {
        RequestId id = _createRankRangeRequest(
            requester1,
            domainAvici,
            1,
            100,
            block.timestamp - 1 days,
            block.timestamp + 1 days,
            block.timestamp + 1 hours,
            block.timestamp + 2 hours,
            0.5 ether
        );

        ScoreRequest memory req = ws.getRequest(id);
        assertEq(req.wallets.length, 0);
        assertEq(req.startRank, 1);
        assertEq(req.rankCount, 100);
    }

    // ============ Creation Tests - Selection Mode ============

    function test_createRequest_FastestSelectionMode() public {
        address[] memory wallets = _singleWalletArray(address(0x1000));

        vm.prank(requester1);
        RequestId id = ws.createRequest{value: 0.5 ether}(
            domainAvici,
            wallets,
            0, 0,
            block.timestamp - 1 days,
            block.timestamp + 1 days,
            block.timestamp + 1 hours,
            block.timestamp + 2 hours,
            BidSelection.Fastest
        );

        ScoreRequest memory req = ws.getRequest(id);
        assertEq(uint8(req.selectionMode), uint8(BidSelection.Fastest));
    }

    // ============ Creation Tests - Validation Errors ============

    function test_createRequest_RevertWhenDomainNotFound() public {
        address[] memory wallets = _singleWalletArray(address(0x1000));

        vm.prank(requester1);
        vm.expectRevert(abi.encodeWithSelector(IWalletScore.DomainNotFound.selector, domainUnregistered));
        ws.createRequest{value: 0.5 ether}(
            domainUnregistered,
            wallets,
            0, 0,
            block.timestamp - 1 days, block.timestamp + 1 days,
            block.timestamp + 1 hours, block.timestamp + 2 hours,
            BidSelection.Cheapest
        );
    }

    function test_createRequest_RevertWhenNoWalletsOrRanks() public {
        vm.prank(requester1);
        vm.expectRevert(abi.encodeWithSelector(IWalletScore.InvalidRequestParams.selector));
        ws.createRequest{value: 0.5 ether}(
            domainAvici,
            new address[](0),
            0, 0,
            block.timestamp - 1 days, block.timestamp + 1 days,
            block.timestamp + 1 hours, block.timestamp + 2 hours,
            BidSelection.Cheapest
        );
    }

    function test_createRequest_RevertWhenQuotingDeadlineInPast() public {
        address[] memory wallets = _singleWalletArray(address(0x1000));

        vm.prank(requester1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IWalletScore.InvalidDeadlines.selector,
                block.timestamp - 1,
                block.timestamp + 2 hours
            )
        );
        ws.createRequest{value: 0.5 ether}(
            domainAvici,
            wallets,
            0, 0,
            block.timestamp - 1 days, block.timestamp + 1 days,
            block.timestamp - 1,
            block.timestamp + 2 hours,
            BidSelection.Cheapest
        );
    }

    function test_createRequest_RevertWhenFulfillmentBeforeQuoting() public {
        address[] memory wallets = _singleWalletArray(address(0x1000));

        vm.prank(requester1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IWalletScore.InvalidDeadlines.selector,
                block.timestamp + 2 hours,
                block.timestamp + 1 hours
            )
        );
        ws.createRequest{value: 0.5 ether}(
            domainAvici,
            wallets,
            0, 0,
            block.timestamp - 1 days, block.timestamp + 1 days,
            block.timestamp + 2 hours,
            block.timestamp + 1 hours,
            BidSelection.Cheapest
        );
    }

    // ============ Cancellation Tests ============

    function test_cancelRequest_InQuotingPhase() public {
        RequestId id = _createSimpleRequest(0.5 ether);

        uint256 requesterBalanceBefore = ws.getWithdrawable(requester1);

        vm.prank(requester1);
        ws.cancelRequest(id);

        _assertRequestStatus(id, RequestStatus.Cancelled);
        assertEq(ws.getWithdrawable(requester1), requesterBalanceBefore + 0.5 ether);
    }

    function test_cancelRequest_EmitsRequestCancelled() public {
        RequestId id = _createSimpleRequest(0.5 ether);

        vm.expectEmit(true, false, false, false);
        emit IWalletScore.RequestCancelled(id);

        vm.prank(requester1);
        ws.cancelRequest(id);
    }

    function test_cancelRequest_InSelectingPhase() public {
        RequestId id = _createSimpleRequest(0.5 ether);

        _submitBidAsPublisher1(id, 0.3 ether, 30 minutes);

        _advancePastQuotingDeadline(id);

        vm.prank(requester1);
        ws.cancelRequest(id);

        _assertRequestStatus(id, RequestStatus.Cancelled);
    }

    function test_cancelRequest_RevertWhenNotRequester() public {
        RequestId id = _createSimpleRequest(0.5 ether);

        vm.prank(nobody);
        vm.expectRevert(abi.encodeWithSelector(IWalletScore.NotRequester.selector, id));
        ws.cancelRequest(id);
    }

    function test_cancelRequest_RevertWhenAssigned() public {
        RequestId id = _createSimpleRequest(0.5 ether);

        _submitBidAsPublisher1(id, 0.3 ether, 30 minutes);

        _advancePastQuotingDeadline(id);
        ws.advanceRequest(id);

        _assertRequestStatus(id, RequestStatus.Assigned);

        vm.prank(requester1);
        vm.expectRevert(
            abi.encodeWithSelector(IWalletScore.RequestNotCancellable.selector, id, RequestStatus.Assigned)
        );
        ws.cancelRequest(id);
    }

    function test_cancelRequest_RevertWhenFulfilled() public {
        RequestId id = _createSimpleRequest(0.5 ether);

        _submitBidAsPublisher1(id, 0.3 ether, 30 minutes);

        _advancePastQuotingDeadline(id);
        ws.advanceRequest(id);

        Entry[] memory entries = _buildSampleEntries(2);
        entries[0].wallet = address(0x1000);
        ScoreSetId scoreSetId =
            _createAndPublishScoreSetWithEntries(publisher1Addr, domainAvici, block.timestamp, entries);

        vm.prank(publisher1Addr);
        ws.fulfillRequest(id, scoreSetId);

        _assertRequestStatus(id, RequestStatus.Fulfilled);

        vm.prank(requester1);
        vm.expectRevert(
            abi.encodeWithSelector(IWalletScore.RequestNotCancellable.selector, id, RequestStatus.Fulfilled)
        );
        ws.cancelRequest(id);
    }

    // ============ Query Tests ============

    function test_getRequest_RevertWhenNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(IWalletScore.RequestNotFound.selector, RequestId.wrap(999)));
        ws.getRequest(RequestId.wrap(999));
    }

    function test_getRequestBids_ReturnsEmptyForNewRequest() public {
        RequestId id = _createSimpleRequest(0.5 ether);

        BidId[] memory bids = ws.getRequestBids(id);
        assertEq(bids.length, 0);
    }
}
