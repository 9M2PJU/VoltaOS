# Phone and Messages

Calls, contacts and SMS of **your phone**, over Bluetooth. Service `phone_service.py` (D-Bus).

**Requirements:** phone [paired](../settings/bluetooth-network.md) and connected; `bluez`,
`bluez-obexd` and PipeWire (calls use PipeWire's HFP profile). On the phone enable
**sharing of contacts and messages** in the Bluetooth device's page, otherwise the lists stay empty.

## Phone

Three tabs:

- **Calls** — *Recent calls* with date and type; tap a row to call back.
- **Contacts** — the address book, with **Search contact**. The number can be *Mobile* and other types.
- **Favorites** — favorite contacts.

There is also the **dial pad** to enter a number (it also opens from the call notification).

During a call, a banner above the music widget shows **Incoming call / Outgoing call /
In call** with the **Answer**, **Decline** or **End** buttons, the **microphone** (mute) and the
dial pad.

## Messages

- List of **conversations** on the left, the thread on the right ("Select a conversation").
- Type and press **Send**: the SMS is sent from the phone.
- When an SMS arrives the **"New message"** notification appears with *Open*.

Contacts, history and messages are downloaded from the phone on connection and cached so
they show immediately next time.

## Data

It stays on the PC; to clear the cache disconnect and forget the phone in the Bluetooth
settings.
