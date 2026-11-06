"""Lossless streaming-style 8x8 tile delta packet for first-hit risk pixels.

Each P-frame records sorted (uint16 tile_id, uint64 bitmask) tuples with
SHA256 bank identity, reference frame index and CRC32. If budget is exceeded,
returns I_REQUIRED (full geometry validation); NEVER silently truncate flags.
This only compacts a WORKLIST, it does not implement GPU first-hit resolve.
"""
from __future__ import annotations
import struct
import zlib
import numpy as np

W=720
N=W*W
TILE=8
TILES_PER_SIDE=W//TILE
TILES=TILES_PER_SIDE**2
MAGIC=b'LIES'
HEADER=struct.Struct('<4sBIII32sI')
RECORD=struct.Struct('<HQ')

def mask_to_records(mask):
    arr=np.asarray(mask,dtype=bool)
    if arr.shape!=(N,):raise ValueError('Expected exact 720x720 risk worklist')
    tiles=arr.reshape(W,W).reshape(TILES_PER_SIDE,TILE,TILES_PER_SIDE,TILE).transpose(0,2,1,3)
    bits=tiles.reshape(TILES,64)
    weights=np.uint64(1)<<np.arange(64,dtype=np.uint64)
    packed=bits.astype(np.uint64)@weights
    ids=np.flatnonzero(packed)
    return [(int(i),int(packed[i])) for i in ids]

def records_to_mask(records):
    result=np.zeros((TILES,64),dtype=bool)
    last=-1
    for index,bits in records:
        if not 0<=index<TILES or index<=last or not 0<bits<1<<64:
            raise ValueError('Repeated, unsorted, empty, or invalid tile record')
        last=index
        result[index]=((np.uint64(bits)>>np.arange(64,dtype=np.uint64))&1)!=0
    return result.reshape(TILES_PER_SIDE,TILES_PER_SIDE,TILE,TILE).transpose(0,2,1,3).reshape(N)

def encode(mask,bank_sha256,frame_index,reference_index,max_tiles=2000):
    if (not isinstance(bank_sha256,str) or len(bank_sha256)!=64 or frame_index<=reference_index
            or reference_index<0 or max_tiles<1):
        raise ValueError('Invalid I/P-frame reference or source identity')
    try:bank=bytes.fromhex(bank_sha256)
    except ValueError as error:raise ValueError('Invalid bank SHA-256') from error
    records=mask_to_records(mask)
    if len(records)>max_tiles:
        return {'mode':'I_REQUIRED','reason':'delta tile budget exceeded; require full geometry query',
                'flagged_tiles':len(records),'max_tiles':max_tiles,
                'encoded':None,'no_flags_dropped':True}
    payload=b''.join(RECORD.pack(i,bits) for i,bits in records)
    header0=HEADER.pack(MAGIC,1,frame_index,reference_index,len(records),bank,0)
    crc=zlib.crc32(header0[:-4]+payload)
    return {'mode':'P','encoded':HEADER.pack(MAGIC,1,frame_index,reference_index,len(records),bank,crc)+payload,
            'flagged_tiles':len(records),'flagged_pixels':int(np.asarray(mask,dtype=bool).sum()),
            'no_flags_dropped':True}

def decode(packet,expected_bank_sha256,expected_reference_index):
    if len(packet)<HEADER.size:raise ValueError('Missing complete frame header')
    magic,version,frame,reference,count,bank,crc=HEADER.unpack_from(packet)
    if magic!=MAGIC or version!=1 or frame<=reference or reference!=expected_reference_index:
        raise ValueError('Stale P-frame or incorrect reference')
    if bank.hex()!=expected_bank_sha256:raise ValueError('Capture source changed: require I-frame')
    payload=packet[HEADER.size:]
    if len(payload)!=count*RECORD.size or count>TILES:
        raise ValueError('Incomplete P-frame records')
    if zlib.crc32(packet[:HEADER.size-4]+payload)!=crc:
        raise ValueError('Corrupted risk packet CRC32')
    records=[RECORD.unpack_from(payload,i*RECORD.size) for i in range(count)]
    return records_to_mask(records),{'frame_index':frame,'reference_index':reference,
                                     'tiles':count,'bank_sha256':bank.hex()}
