'use strict';

import { providerBundle } from "./provider-bundle.ts";
let encodedTables;

function decodeByteTable(name) {
  const base64 = encodedTables[name];
  if (typeof base64 !== 'string' || !base64.length) {
    throw new Error(`Missing embedded WBSK table: ${name}`);
  }
  const buf = Buffer.from(base64, 'base64');
  if (buf.length !== 256) {
    throw new Error(`WBSK table ${name} has unexpected size ${buf.length} (expected 256)`);
  }
  return buf;
}

function decodeU32Table(name) {
  const base64 = encodedTables[name];
  if (typeof base64 !== 'string' || !base64.length) {
    throw new Error(`Missing embedded WBSK table: ${name}`);
  }
  const buf = Buffer.from(base64, 'base64');
  if (buf.length !== 1024) {
    throw new Error(`WBSK table ${name} has unexpected size ${buf.length} (expected 1024)`);
  }
  const table = new Uint32Array(256);
  for (let i = 0; i < 256; i++) {
    table[i] = buf.readUInt32LE(i * 4);
  }
  return table;
}

// Encrypt tables
let ENC_INIT_XOR;
let ENC_ROUND_XOR;
let ENC_SBOX;
let ENC_FINAL_XOR;
let ENC_TE0;
let ENC_TE1;
let ENC_TE2;
let ENC_TE3;

// Decrypt tables
let DEC_INIT_XOR;
let DEC_ROUND_XOR;
let DEC_INV_SBOX;
let DEC_FINAL_XOR;
let DEC_TD0;
let DEC_TD1;
let DEC_TD2;
let DEC_TD3;

// --- Static WBSK keys (device-bound, not per-session) ---
let WBSK_KEYS;

function ensureCodec() {
  if (WBSK_KEYS) return;
  const codec = providerBundle().auto?.codec;
  if (!codec) throw new Error("OpenAuto provider is not configured");
  encodedTables = codec.tables;
  ENC_INIT_XOR = decodeByteTable('encInitXor'); ENC_ROUND_XOR = decodeByteTable('encRoundXor'); ENC_SBOX = decodeByteTable('encSbox'); ENC_FINAL_XOR = decodeByteTable('encFinalXor');
  ENC_TE0 = decodeU32Table('encTe0'); ENC_TE1 = decodeU32Table('encTe1'); ENC_TE2 = decodeU32Table('encTe2'); ENC_TE3 = decodeU32Table('encTe3');
  DEC_INIT_XOR = decodeByteTable('decInitXor'); DEC_ROUND_XOR = decodeByteTable('decRoundXor'); DEC_INV_SBOX = decodeByteTable('decInvSbox'); DEC_FINAL_XOR = decodeByteTable('decFinalXor');
  DEC_TD0 = decodeU32Table('decTd0'); DEC_TD1 = decodeU32Table('decTd1'); DEC_TD2 = decodeU32Table('decTd2'); DEC_TD3 = decodeU32Table('decTd3');
  WBSK_KEYS = codec;
}

// --- Protected XOR operation ---
// Nibble-decomposed lookup: operates in an encoded byte domain.
function protXor(table, a, b) {
  const hi = table[((a >> 4) << 4) ^ (b >> 4)] & 0xF0;
  const lo = (table[((a & 0xF) << 4) ^ (b & 0xF)] >> 4) & 0x0F;
  return hi | lo;
}

// --- Parse WBC key blob ---
function parseWbcKey(hexStr) {
  const raw = Buffer.from(hexStr, 'hex');
  if (raw.length < 5) {
    throw new Error(`WBC key blob too short: ${raw.length} bytes`);
  }
  const mode = raw[0] ^ raw[3];

  const keyData = Buffer.alloc(raw.length - 4);
  for (let i = 4; i < raw.length; i++) {
    keyData[i - 4] = raw[i] ^ raw[i % 3];
  }

  let keySizeBits;
  if ([0, 1].includes(mode)) keySizeBits = 0x80;
  else if ([2, 3].includes(mode)) keySizeBits = 0xC0;
  else if ([4, 5].includes(mode)) keySizeBits = 0x80;
  else if ([6, 7].includes(mode)) keySizeBits = 0x40;
  else if ([8, 9].includes(mode)) keySizeBits = 0xC0;
  else if ([0xa, 0xb].includes(mode)) keySizeBits = 0x80;
  else if ([0xc, 0xd].includes(mode)) keySizeBits = 0x80;
  else if ([0xe, 0xf].includes(mode)) keySizeBits = 0xC0;
  else if ([0x10, 0x11].includes(mode)) keySizeBits = 0x100;
  else if ([0x12, 0x13].includes(mode)) keySizeBits = 0x40;
  else if ([0x14, 0x15].includes(mode)) keySizeBits = 0xC0;
  else if ([0x16, 0x17].includes(mode)) keySizeBits = 0x80;
  else throw new Error(`Unknown WBC mode: 0x${mode.toString(16)}`);

  const numRounds = (keySizeBits >> 5) + 6;
  const isDecrypt = mode & 1;
  const blockSize = ([6, 7, 0x12, 0x13].includes(mode)) ? 8 : 16;

  return { keyData, keySizeBits, numRounds, isDecrypt, blockSize, mode };
}

// --- WBC AES Encrypt Block (16 bytes) ---
function wbcEncryptBlock(input, keyData, numRounds) {
  const state = Buffer.alloc(16);
  const temp1 = Buffer.alloc(16);
  const temp2 = Buffer.alloc(16);

  for (let i = 0; i < 16; i++) {
    state[i] = protXor(ENC_INIT_XOR, input[i], keyData[i]);
  }

  for (let r = 1; r < numRounds; r++) {
    // Te0 [0,4,8,12]
    for (let c = 0; c < 4; c++) {
      const v = ENC_TE0[state[c * 4]];
      temp1[c * 4] = (v >> 24) & 0xFF; temp1[c * 4 + 1] = (v >> 16) & 0xFF;
      temp1[c * 4 + 2] = (v >> 8) & 0xFF; temp1[c * 4 + 3] = v & 0xFF;
    }
    // Te1 [5,9,13,1]
    const te1i = [5, 9, 13, 1];
    for (let c = 0; c < 4; c++) {
      const v = ENC_TE1[state[te1i[c]]];
      temp2[c * 4] = (v >> 24) & 0xFF; temp2[c * 4 + 1] = (v >> 16) & 0xFF;
      temp2[c * 4 + 2] = (v >> 8) & 0xFF; temp2[c * 4 + 3] = v & 0xFF;
    }
    for (let i = 0; i < 16; i++) temp1[i] = protXor(ENC_ROUND_XOR, temp1[i], temp2[i]);
    // Te2 [10,14,2,6]
    const te2i = [10, 14, 2, 6];
    for (let c = 0; c < 4; c++) {
      const v = ENC_TE2[state[te2i[c]]];
      temp2[c * 4] = (v >> 24) & 0xFF; temp2[c * 4 + 1] = (v >> 16) & 0xFF;
      temp2[c * 4 + 2] = (v >> 8) & 0xFF; temp2[c * 4 + 3] = v & 0xFF;
    }
    for (let i = 0; i < 16; i++) temp1[i] = protXor(ENC_ROUND_XOR, temp1[i], temp2[i]);
    // Te3 [15,3,7,11]
    const te3i = [15, 3, 7, 11];
    for (let c = 0; c < 4; c++) {
      const v = ENC_TE3[state[te3i[c]]];
      temp2[c * 4] = (v >> 24) & 0xFF; temp2[c * 4 + 1] = (v >> 16) & 0xFF;
      temp2[c * 4 + 2] = (v >> 8) & 0xFF; temp2[c * 4 + 3] = v & 0xFF;
    }
    for (let i = 0; i < 16; i++) temp1[i] = protXor(ENC_ROUND_XOR, temp1[i], temp2[i]);
    // AddRoundKey
    const rkOff = r * 16;
    for (let i = 0; i < 16; i++) state[i] = protXor(ENC_ROUND_XOR, temp1[i], keyData[rkOff + i]);
  }

  // Final round: S-box + ShiftRows + AddRoundKey
  const sr = [0, 5, 10, 15, 4, 9, 14, 3, 8, 13, 2, 7, 12, 1, 6, 11];
  for (let i = 0; i < 16; i++) temp1[i] = ENC_SBOX[state[sr[i]]];
  const output = Buffer.alloc(16);
  const frkOff = numRounds * 16;
  for (let i = 0; i < 16; i++) output[i] = protXor(ENC_FINAL_XOR, temp1[i], keyData[frkOff + i]);
  return output;
}

// --- WBC AES Decrypt Block (16 bytes) ---
function wbcDecryptBlock(input, keyData, numRounds) {
  const state = Buffer.alloc(16);
  const temp1 = Buffer.alloc(16);
  const temp2 = Buffer.alloc(16);

  for (let i = 0; i < 16; i++) {
    state[i] = protXor(DEC_INIT_XOR, input[i], keyData[i]);
  }

  for (let r = 1; r < numRounds; r++) {
    // Td0 [0,4,8,12]
    for (let c = 0; c < 4; c++) {
      const v = DEC_TD0[state[c * 4]];
      temp1[c * 4] = (v >> 24) & 0xFF; temp1[c * 4 + 1] = (v >> 16) & 0xFF;
      temp1[c * 4 + 2] = (v >> 8) & 0xFF; temp1[c * 4 + 3] = v & 0xFF;
    }
    // Td1 [13,1,5,9] (InvShiftRows)
    const td1i = [13, 1, 5, 9];
    for (let c = 0; c < 4; c++) {
      const v = DEC_TD1[state[td1i[c]]];
      temp2[c * 4] = (v >> 24) & 0xFF; temp2[c * 4 + 1] = (v >> 16) & 0xFF;
      temp2[c * 4 + 2] = (v >> 8) & 0xFF; temp2[c * 4 + 3] = v & 0xFF;
    }
    for (let i = 0; i < 16; i++) temp1[i] = protXor(DEC_ROUND_XOR, temp1[i], temp2[i]);
    // Td2 [10,14,2,6]
    const td2i = [10, 14, 2, 6];
    for (let c = 0; c < 4; c++) {
      const v = DEC_TD2[state[td2i[c]]];
      temp2[c * 4] = (v >> 24) & 0xFF; temp2[c * 4 + 1] = (v >> 16) & 0xFF;
      temp2[c * 4 + 2] = (v >> 8) & 0xFF; temp2[c * 4 + 3] = v & 0xFF;
    }
    for (let i = 0; i < 16; i++) temp1[i] = protXor(DEC_ROUND_XOR, temp1[i], temp2[i]);
    // Td3 [7,11,15,3] (InvShiftRows)
    const td3i = [7, 11, 15, 3];
    for (let c = 0; c < 4; c++) {
      const v = DEC_TD3[state[td3i[c]]];
      temp2[c * 4] = (v >> 24) & 0xFF; temp2[c * 4 + 1] = (v >> 16) & 0xFF;
      temp2[c * 4 + 2] = (v >> 8) & 0xFF; temp2[c * 4 + 3] = v & 0xFF;
    }
    for (let i = 0; i < 16; i++) temp1[i] = protXor(DEC_ROUND_XOR, temp1[i], temp2[i]);
    // AddRoundKey
    const rkOff = r * 16;
    for (let i = 0; i < 16; i++) state[i] = protXor(DEC_ROUND_XOR, temp1[i], keyData[rkOff + i]);
  }

  // Final round: inv S-box + InvShiftRows + AddRoundKey
  const invSr = [0, 13, 10, 7, 4, 1, 14, 11, 8, 5, 2, 15, 12, 9, 6, 3];
  for (let i = 0; i < 16; i++) temp1[i] = DEC_INV_SBOX[state[invSr[i]]];
  const output = Buffer.alloc(16);
  const frkOff = numRounds * 16;
  for (let i = 0; i < 16; i++) output[i] = protXor(DEC_FINAL_XOR, temp1[i], keyData[frkOff + i]);
  return output;
}

// --- CBC mode ---
function wbcEncryptCbc(plaintext, keyData, numRounds, iv) {
  const blockCount = plaintext.length / 16;
  const output = Buffer.alloc(plaintext.length);
  let prev = iv;

  for (let b = 0; b < blockCount; b++) {
    const block = Buffer.alloc(16);
    for (let i = 0; i < 16; i++) {
      block[i] = plaintext[b * 16 + i] ^ prev[i];
    }
    const enc = wbcEncryptBlock(block, keyData, numRounds);
    enc.copy(output, b * 16);
    prev = enc;
  }
  return output;
}

function wbcDecryptCbc(ciphertext, keyData, numRounds, iv) {
  const blockCount = ciphertext.length / 16;
  const output = Buffer.alloc(ciphertext.length);
  let prev = iv;

  for (let b = 0; b < blockCount; b++) {
    const block = ciphertext.subarray(b * 16, b * 16 + 16);
    const dec = wbcDecryptBlock(block, keyData, numRounds);
    for (let i = 0; i < 16; i++) {
      output[b * 16 + i] = dec[i] ^ prev[i];
    }
    prev = block;
  }
  return output;
}

// --- Nibble codec ---
// Per-byte nibble substitution between plaintext and WBC encoded domain.
const NIBBLE_ENCODE = [0x0,0x8,0x4,0xc,0x1,0x9,0x5,0xd,0x2,0xa,0x6,0xe,0x3,0xb,0x7,0xf];
const NIBBLE_DECODE = [0x0,0x4,0x8,0xc,0x2,0x6,0xa,0xe,0x1,0x5,0x9,0xd,0x3,0x7,0xb,0xf];

function nibbleEncode(buf) {
  const out = Buffer.alloc(buf.length);
  for (let i = 0; i < buf.length; i++) {
    out[i] = (NIBBLE_ENCODE[buf[i] >> 4] << 4) | NIBBLE_ENCODE[buf[i] & 0xf];
  }
  return out;
}

function nibbleDecode(buf) {
  const out = Buffer.alloc(buf.length);
  for (let i = 0; i < buf.length; i++) {
    out[i] = (NIBBLE_DECODE[buf[i] >> 4] << 4) | NIBBLE_DECODE[buf[i] & 0xf];
  }
  return out;
}

// --- PKCS7 padding helper ---
function stripPkcs7(buf) {
  const padVal = buf[buf.length - 1];
  if (padVal < 1 || padVal > 16) return buf;
  for (let i = buf.length - padVal; i < buf.length; i++) {
    if (buf[i] !== padVal) return buf;
  }
  return buf.subarray(0, buf.length - padVal);
}

// --- Two-layer WBSK envelope decrypt ---
function decryptWbskEnvelope(base64Str, outerKeyHex, innerKeyHex, outerSessionIvHex) {
  // 1. Base64 decode → raw envelope bytes (version + envelopeIV + ciphertext)
  const raw = Buffer.from(base64Str, 'base64');

  // 2. Nibble-encode all raw bytes + pad with 256 zero bytes
  const outerEncoded = Buffer.concat([nibbleEncode(raw), Buffer.alloc(256, 0)]);

  // 3. WBC decrypt CBC with outer key and session IV
  const outerKey = parseWbcKey(outerKeyHex);
  const outerIv = Buffer.from(outerSessionIvHex, 'hex');
  const outerDecrypted = wbcDecryptCbc(outerEncoded, outerKey.keyData, outerKey.numRounds, outerIv);

  // 4. Nibble-decode content region and strip PKCS7 padding
  const outerContent = stripPkcs7(nibbleDecode(outerDecrypted.subarray(0, raw.length)));
  const contentLen = outerContent.length;

  // 5. Split: base64(inner) is first (contentLen-16) bytes,
  //    inner session IV is last 16 bytes from raw WBC output (already in encoded domain)
  const innerBase64 = outerContent.subarray(0, contentLen - 16).toString('latin1');
  const innerIv = outerDecrypted.subarray(contentLen - 16, contentLen);

  // 6. Base64 decode inner envelope + nibble-encode + pad
  const innerRaw = Buffer.from(innerBase64, 'base64');
  const innerEncoded = Buffer.concat([nibbleEncode(innerRaw), Buffer.alloc(256, 0)]);

  // 7. WBC decrypt CBC with inner key and session IV
  const innerKey = parseWbcKey(innerKeyHex);
  const innerDecrypted = wbcDecryptCbc(innerEncoded, innerKey.keyData, innerKey.numRounds, innerIv);

  // 8. Nibble-decode content region + strip PKCS7 → plaintext JSON
  const innerContent = stripPkcs7(nibbleDecode(innerDecrypted.subarray(0, innerRaw.length)));
  return innerContent.toString('utf8');
}

// --- Nibble domain helpers for WBC encrypt ---
// "Mystery encode": per-nibble ENCODE[ENCODE[n^8]] — converts plaintext to WBC encrypt input domain.
const MYSTERY_ENCODE = new Array(16);
for (let n = 0; n < 16; n++) MYSTERY_ENCODE[n] = NIBBLE_ENCODE[NIBBLE_ENCODE[n ^ 8]];
// [4,6,5,7,c,e,d,f,0,2,1,3,8,a,9,b]

function wbcInputEncode(buf) {
  const out = Buffer.alloc(buf.length);
  for (let i = 0; i < buf.length; i++) {
    out[i] = (MYSTERY_ENCODE[buf[i] >> 4] << 4) | MYSTERY_ENCODE[buf[i] & 0xf];
  }
  return out;
}

// "Transform": per-nibble ENCODE[ENCODE[n]] — converts WBC encrypt output to raw envelope domain.
function wbcOutputDecode(buf) {
  const out = Buffer.alloc(buf.length);
  for (let i = 0; i < buf.length; i++) {
    out[i] = (NIBBLE_ENCODE[NIBBLE_ENCODE[buf[i] >> 4]] << 4) |
             NIBBLE_ENCODE[NIBBLE_ENCODE[buf[i] & 0xf]];
  }
  return out;
}

// PKCS7 padding in the WBC input domain (mystery-encoded pad values).
function addWbcPkcs7(buf, blockSize = 16) {
  const remainder = buf.length % blockSize;
  const padN = remainder === 0 ? blockSize : blockSize - remainder;
  const padByte = (MYSTERY_ENCODE[padN >> 4] << 4) | MYSTERY_ENCODE[padN & 0xf];
  return Buffer.concat([buf, Buffer.alloc(padN, padByte)]);
}

// --- Two-layer WBSK envelope encrypt ---
function encryptWbskEnvelope(plaintext, innerEncKeyHex, innerEncIvHex, outerEncKeyHex, outerEncIvHex) {
  // 1. Mystery-encode plaintext UTF-8 bytes + PKCS7 pad (in mystery domain)
  const plainBuf = Buffer.from(plaintext, 'utf8');
  const innerPadded = addWbcPkcs7(wbcInputEncode(plainBuf));

  // 2. WBC encrypt CBC with inner key + IV
  const innerKey = parseWbcKey(innerEncKeyHex);
  const innerIv = Buffer.from(innerEncIvHex, 'hex');
  const innerEncrypted = wbcEncryptCbc(innerPadded, innerKey.keyData, innerKey.numRounds, innerIv);

  // 3. Transform WBC output to raw domain → base64
  const innerRaw = wbcOutputDecode(innerEncrypted);
  const innerB64 = innerRaw.toString('base64');

  // 4. Build outer content: base64 string + transform(innerEncIV), then mystery-encode
  const outerContentPlain = Buffer.concat([
    Buffer.from(innerB64, 'latin1'),
    wbcOutputDecode(innerIv),
  ]);
  const outerMystery = addWbcPkcs7(wbcInputEncode(outerContentPlain));

  // 5. WBC encrypt CBC with outer key + IV
  const outerKey = parseWbcKey(outerEncKeyHex);
  const outerIv = Buffer.from(outerEncIvHex, 'hex');
  const outerEncrypted = wbcEncryptCbc(outerMystery, outerKey.keyData, outerKey.numRounds, outerIv);

  // 6. Transform WBC output to raw domain → base64
  return wbcOutputDecode(outerEncrypted).toString('base64');
}

// --- Convenience wrappers using hardcoded keys ---
function encryptEnvelope(plaintext) {
  ensureCodec();
  return encryptWbskEnvelope(
    plaintext,
    WBSK_KEYS.innerEncryptKey,
    WBSK_KEYS.innerEncryptIv,
    WBSK_KEYS.outerEncryptKey,
    WBSK_KEYS.outerEncryptIv,
  );
}

function decryptEnvelope(base64Str) {
  ensureCodec();
  return decryptWbskEnvelope(
    base64Str,
    WBSK_KEYS.outerDecryptKey,
    WBSK_KEYS.innerDecryptKey,
    WBSK_KEYS.outerDecryptIv,
  );
}

export { encryptEnvelope, decryptEnvelope };
