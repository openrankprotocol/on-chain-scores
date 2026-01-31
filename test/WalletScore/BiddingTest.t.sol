// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {WalletScoreTestBase} from "./WalletScoreTestBase.sol";
import {IWalletScore} from "src/WalletScore/IWalletScore.sol";
import {
    DomainId,
    ScoreSetId,
    RequestId,
    PublisherId,
    BidId,
    BidSelection,
    RequestStatus,
    BidStatus,
    ScoreRequest,
    Bid,
    Entry
} from "src/WalletScore/Types.sol";

contract BiddingTest is WalletScoreTestBase {
    RequestId internal requestId;

    function setUp() public override {
        super.setUp();
        _setupFullFixture();
        requestId = _createSimpleRequest(1 ether);
    }

    // ============ Bid Submission Tests ============

    function test_submitBid_Success() public {
        BidId bidId = _submitBidAsPublisher1(requestId, 0.5 ether, 30 minutes);

        Bid memory bid = ws.getBid(bidId);
        assertEq(RequestId.unwrap(bid.requestId), RequestId.unwrap(requestId));
        assertEq(PublisherId.unwrap(bid.publisher), PublisherId.unwrap(publisher1Id));
        assertEq(bid.price, 0.5 ether);
        assertEq(bid.promisedDuration, 30 minutes);
        assertEq(bid.submittedAt, block.timestamp);
        assertEq(bid.selectedAt, 0);
        assertEq(uint8(bid.status), uint8(BidStatus.Pending));
    }

    function test_submitBid_EmitsBidSubmitted() public {
        vm.expectEmit(true, true, true, true);
        emit IWalletScore.BidSubmitted(BidId.wrap(1), requestId, publisher1Id, 0.5 ether, 30 minutes);

        _submitBidAsPublisher1(requestId, 0.5 ether, 30 minutes);
    }

    function test_submitBid_AssignsIncrementingIds() public {
        BidId bid1 = _submitBidAsPublisher1(requestId, 0.5 ether, 30 minutes);
        BidId bid2 = _submitBidAsPublisher2(requestId, 0.4 ether, 25 minutes);
        BidId bid3 = _submitBidAsPublisher3(requestId, 0.6 ether, 20 minutes);

        assertEq(BidId.unwrap(bid1), 1);
        assertEq(BidId.unwrap(bid2), 2);
        assertEq(BidId.unwrap(bid3), 3);
    }

    function test_submitBid_MultipleBidsFromSamePublisher() public {
        BidId bid1 = _submitBidAsPublisher1(requestId, 0.5 ether, 30 minutes);
        BidId bid2 = _submitBidAsPublisher1(requestId, 0.4 ether, 25 minutes);

        assertEq(BidId.unwrap(bid1), 1);
        assertEq(BidId.unwrap(bid2), 2);

        BidId[] memory bids = ws.getRequestBids(requestId);
        assertEq(bids.length, 2);
    }

    function test_submitBid_AddsToBidList() public {
        _submitBidAsPublisher1(requestId, 0.5 ether, 30 minutes);
        _submitBidAsPublisher2(requestId, 0.4 ether, 25 minutes);

        BidId[] memory bids = ws.getRequestBids(requestId);
        assertEq(bids.length, 2);
    }

    // ============ Bid Validation Tests ============

    function test_submitBid_RevertWhenNotPublisher() public {
        vm.prank(nobody);
        vm.expectRevert();
        ws.submitBid(requestId, 0.5 ether, 30 minutes);
    }

    function test_submitBid_RevertWhenRequestNotFound() public {
        vm.prank(publisher1Addr);
        vm.expectRevert(abi.encodeWithSelector(IWalletScore.RequestNotFound.selector, RequestId.wrap(999)));
        ws.submitBid(RequestId.wrap(999), 0.5 ether, 30 minutes);
    }

    function test_submitBid_RevertWhenPastQuotingDeadline() public {
        _advancePastQuotingDeadline(requestId);

        vm.prank(publisher1Addr);
        vm.expectRevert(
            abi.encodeWithSelector(IWalletScore.RequestNotInQuotingPhase.selector, requestId, RequestStatus.Quoting)
        );
        ws.submitBid(requestId, 0.5 ether, 30 minutes);
    }

    function test_submitBid_RevertWhenInsufficientBond() public {
        vm.prank(publisher1Addr);
        ws.withdrawBond(DEFAULT_BOND);

        vm.prank(publisher1Addr);
        vm.expectRevert(abi.encodeWithSelector(IWalletScore.InsufficientBond.selector, publisher1Id, MIN_BOND, 0));
        ws.submitBid(requestId, 0.5 ether, 30 minutes);
    }

    function test_submitBid_RevertWhenPriceExceedsBudget() public {
        vm.prank(publisher1Addr);
        vm.expectRevert(abi.encodeWithSelector(IWalletScore.PriceExceedsBudget.selector, 2 ether, 1 ether));
        ws.submitBid(requestId, 2 ether, 30 minutes);
    }

    function test_submitBid_RevertWhenPromisedDurationTooLong() public {
        ScoreRequest memory req = ws.getRequest(requestId);
        uint256 availableTime = req.fulfillmentDeadline - req.quotingDeadline;

        vm.prank(publisher1Addr);
        vm.expectRevert(
            abi.encodeWithSelector(IWalletScore.PromisedDurationExceedsDeadline.selector, 2 hours, availableTime)
        );
        ws.submitBid(requestId, 0.5 ether, 2 hours);
    }

    function test_submitBid_RevertWhenPublisherDenylisted() public {
        _denylistPublisher1For(1 days);

        vm.prank(publisher1Addr);
        vm.expectRevert(
            abi.encodeWithSelector(IWalletScore.PublisherIsDenylisted.selector, publisher1Id, block.timestamp + 1 days)
        );
        ws.submitBid(requestId, 0.5 ether, 30 minutes);
    }

    function test_submitBid_AllowedAfterDenylistExpires() public {
        _denylistPublisher1For(1 days);

        skip(1 days + 1);

        RequestId newRequest = _createSimpleRequest(1 ether);

        BidId bidId = _submitBidAsPublisher1(newRequest, 0.5 ether, 30 minutes);
        assertTrue(BidId.unwrap(bidId) > 0);
    }

    // ============ Bid Selection Tests - Cheapest Mode ============

    function test_advanceRequest_SelectsCheapestBid() public {
        _submitBidAsPublisher1(requestId, 0.5 ether, 30 minutes);
        BidId cheapestBid = _submitBidAsPublisher2(requestId, 0.3 ether, 30 minutes);
        _submitBidAsPublisher3(requestId, 0.7 ether, 30 minutes);

        _advancePastQuotingDeadline(requestId);
        ws.advanceRequest(requestId);

        ScoreRequest memory req = ws.getRequest(requestId);
        assertEq(BidId.unwrap(req.currentBid), BidId.unwrap(cheapestBid));
        assertEq(uint8(req.status), uint8(RequestStatus.Assigned));
    }

    function test_advanceRequest_EmitsBidSelected() public {
        _submitBidAsPublisher1(requestId, 0.5 ether, 30 minutes);
        BidId cheapestBid = _submitBidAsPublisher2(requestId, 0.3 ether, 30 minutes);

        _advancePastQuotingDeadline(requestId);

        vm.expectEmit(true, true, true, false);
        emit IWalletScore.BidSelected(requestId, cheapestBid, publisher2Id);

        ws.advanceRequest(requestId);
    }

    function test_advanceRequest_SetsBidStatusToSelected() public {
        BidId bidId = _submitBidAsPublisher1(requestId, 0.5 ether, 30 minutes);

        _advancePastQuotingDeadline(requestId);
        ws.advanceRequest(requestId);

        Bid memory bid = ws.getBid(bidId);
        assertEq(uint8(bid.status), uint8(BidStatus.Selected));
        assertTrue(bid.selectedAt > 0);
    }

    // ============ Bid Selection Tests - Fastest Mode ============

    function test_advanceRequest_SelectsFastestBid() public {
        RequestId fastestModeRequest = _createFastestModeRequest();

        _submitBidAsPublisher1(fastestModeRequest, 0.3 ether, 30 minutes);
        BidId fastestBid = _submitBidAsPublisher2(fastestModeRequest, 0.5 ether, 15 minutes);
        _submitBidAsPublisher3(fastestModeRequest, 0.4 ether, 25 minutes);

        _advancePastQuotingDeadline(fastestModeRequest);
        ws.advanceRequest(fastestModeRequest);

        ScoreRequest memory req = ws.getRequest(fastestModeRequest);
        assertEq(BidId.unwrap(req.currentBid), BidId.unwrap(fastestBid));
    }

    // ============ Advance Request - Edge Cases ============

    function test_advanceRequest_NoOpDuringQuotingPhase() public {
        _submitBidAsPublisher1(requestId, 0.5 ether, 30 minutes);

        ws.advanceRequest(requestId);

        _assertRequestStatus(requestId, RequestStatus.Quoting);
    }

    function test_advanceRequest_FailsWhenNoBids() public {
        _advancePastQuotingDeadline(requestId);
        ws.advanceRequest(requestId);

        _assertRequestStatus(requestId, RequestStatus.Failed);
        _assertWithdrawable(requester1, 1 ether);
    }

    function test_advanceRequest_EmitsRequestFailed() public {
        _advancePastQuotingDeadline(requestId);

        vm.expectEmit(true, false, false, false);
        emit IWalletScore.RequestFailed(requestId);

        ws.advanceRequest(requestId);
    }

    function test_advanceRequest_SkipsBidderWithInsufficientBond() public {
        _submitBidAsPublisher1(requestId, 0.3 ether, 30 minutes);

        _fundAndDepositBondForPublisher2(1 ether);
        BidId bid2 = _submitBidAsPublisher2(requestId, 0.4 ether, 30 minutes);

        vm.prank(admin);
        ws.setMinPublisherBond(1.5 ether);

        _advancePastQuotingDeadline(requestId);
        ws.advanceRequest(requestId);

        ScoreRequest memory req = ws.getRequest(requestId);
        assertEq(BidId.unwrap(req.currentBid), BidId.unwrap(bid2));
    }

    function test_advanceRequest_SkipsDenylistedBidder() public {
        _submitBidAsPublisher1(requestId, 0.3 ether, 30 minutes);
        BidId bid2 = _submitBidAsPublisher2(requestId, 0.4 ether, 30 minutes);

        _denylistPublisher1For(1 days);

        _advancePastQuotingDeadline(requestId);
        ws.advanceRequest(requestId);

        ScoreRequest memory req = ws.getRequest(requestId);
        assertEq(BidId.unwrap(req.currentBid), BidId.unwrap(bid2));
    }

    function test_advanceRequest_SkipsBidWithExpiredTiming() public {
        BidId bid1 = _submitBidAsPublisher1(requestId, 0.3 ether, 30 minutes);
        _submitBidAsPublisher2(requestId, 0.4 ether, 55 minutes);

        _advanceToJustBeforeQuotingDeadline(requestId);
        skip(10 minutes);

        ws.advanceRequest(requestId);

        ScoreRequest memory req = ws.getRequest(requestId);
        assertEq(BidId.unwrap(req.currentBid), BidId.unwrap(bid1));
    }

    function test_advanceRequest_IdempotentWhenAssigned() public {
        _submitBidAsPublisher1(requestId, 0.5 ether, 30 minutes);

        _advancePastQuotingDeadline(requestId);
        ws.advanceRequest(requestId);

        ScoreRequest memory reqBefore = ws.getRequest(requestId);

        ws.advanceRequest(requestId);
        ws.advanceRequest(requestId);

        ScoreRequest memory reqAfter = ws.getRequest(requestId);
        assertEq(BidId.unwrap(reqAfter.currentBid), BidId.unwrap(reqBefore.currentBid));
        assertEq(uint8(reqAfter.status), uint8(RequestStatus.Assigned));
    }

    function test_advanceRequest_IdempotentWhenFulfilled() public {
        _submitBidAsPublisher1(requestId, 0.5 ether, 30 minutes);

        _advancePastQuotingDeadline(requestId);
        ws.advanceRequest(requestId);

        Entry[] memory entries = _buildSampleEntries(2);
        entries[0].wallet = address(0x1000);
        ScoreSetId scoreSetId =
            _createAndPublishScoreSetWithEntries(publisher1Addr, domainAvici, block.timestamp, entries);

        vm.prank(publisher1Addr);
        ws.fulfillRequest(requestId, scoreSetId);

        ws.advanceRequest(requestId);

        _assertRequestStatus(requestId, RequestStatus.Fulfilled);
    }

    // ============ Bid Query Tests ============

    function test_getBid_RevertWhenNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(IWalletScore.BidNotFound.selector, BidId.wrap(999)));
        ws.getBid(BidId.wrap(999));
    }

    // ============ Helpers ============

    function _createFastestModeRequest() internal returns (RequestId) {
        address[] memory wallets = _singleWalletArray(address(0x1000));

        vm.prank(requester1);
        return ws.createRequest{value: 1 ether}(
            domainAvici,
            wallets,
            0,
            0,
            block.timestamp - 1 days,
            block.timestamp + 1 days,
            block.timestamp + 1 hours,
            block.timestamp + 2 hours,
            BidSelection.Fastest
        );
    }

    function _denylistPublisher1For(uint256 duration) internal {
        vm.store(address(ws), _getPublisherDenylistSlot(publisher1Id), bytes32(block.timestamp + duration));
    }

    function _getPublisherDenylistSlot(PublisherId pubId) internal pure returns (bytes32) {
        // _publishers mapping is at storage slot 1
        uint256 publishersSlot = 1;
        bytes32 publisherBaseSlot = keccak256(abi.encode(PublisherId.unwrap(pubId), publishersSlot));
        // denylistUntil is the 4th field (index 3) in the Publisher struct
        return bytes32(uint256(publisherBaseSlot) + 3);
    }
}
