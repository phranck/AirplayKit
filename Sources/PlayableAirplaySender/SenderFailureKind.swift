//
//  SenderFailureKind.swift
//  What a failure is, decided once.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

import Foundation

/**
 The kinds of failure a caller is told apart.

 Both faces of this package report failures, the Swift one as an enumeration and
 the C one as a number, and each used to decide for itself which errors belonged
 where. Two answers to one question, kept in step by hand, and a new error added
 to one of them would have been classified by the other as something it is not.

 So the question is answered here, once, and both faces translate the answer
 into their own vocabulary.
 */
public enum SenderFailureKind {
    /// The receiver could not be reached at all.
    case unreachable

    /// It refused to pair, so it does not hold the same secret or would not let this sender in.
    case pairingRefused

    /// The session was open and is not any more.
    case sessionEnded

    /// The caller passed something unusable.
    case invalidRequest

    /// Anything else, which a caller cannot act on beyond reporting it.
    case senderFailed

    /**
     Classifies a failure.

     @param error Whatever was thrown.
     */
    public init(_ error: Error) {
        switch error {
        case TCPFailure.hostCouldNotBeResolved, TCPFailure.connectionRefused,
             TCPFailure.socketCouldNotBeOpened, TCPFailure.timedOut:
            self = .unreachable

        // Every way a connection that was open stops being usable. They are
        // told apart at the socket so a log says which happened, and they mean
        // the same thing to a caller: the session is over.
        case TCPFailure.connectionClosed, TCPFailure.connectionWasStopped,
             TCPFailure.messageWasPartlySent, SenderFailure.receiverAnnouncedNoClock:
            self = .sessionEnded

        case is SRPError, is PairSetupFailure:
            self = .pairingRefused

        // A receiver that answers something other than 200, or answers with
        // something that is not a message, is refusing rather than failing.
        case RTSPFailure.receiverAnswered, RTSPFailure.answerIsNotReadable:
            self = .pairingRefused

        // Nothing to do with the receiver. The ports the clock listens on are
        // below 1024, and this machine would not grant them.
        case is PTPFailure:
            self = .senderFailed

        default:
            self = .senderFailed
        }
    }
}
