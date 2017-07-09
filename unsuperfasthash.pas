unit unSuperFastHash;
(*
  A Delphi and assembly translation of the SuperFastHash function by
  Paul Hsieh (http://www.azillionmonkeys.com/qed/hash.html).

  I got the idea for translating it due to borland.public.delphi.language.basm.
  See the full discussion at:
  http://groups.google.com/group/borland.public.delphi.language.basm/
  browse_thread/thread/96482ba4d1d5a016/7745466ab714c3b3

 ***** BEGIN LICENSE BLOCK *****
 * Version: MPL 1.1/GPL 2.0/LGPL 2.1
 *
 * The contents of this file are subject to the Mozilla Public License Version
 * 1.1 (the "License"); you may not use this file except in compliance with
 * the License. You may obtain a copy of the License at
 * http://www.mozilla.org/MPL/
 *
 * Software distributed under the License is distributed on an "AS IS" basis,
 * WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License
 * for the specific language governing rights and limitations under the
 * License.
 *
 * The Original Code is SuperFastHash Delphi and BASM translation.
 *
 * The Initial Developer of the Original Code is
 * Davy Landman.
 * Portions created by the Initial Developer are Copyright (C) 2007
 * the Initial Developer. All Rights Reserved.
 *
 * Contributor(s):
 *
 *
 * Alternatively, the contents of this file may be used under the terms of
 * either the GNU General Public License Version 2 or later (the "GPL"), or
 * the GNU Lesser General Public License Version 2.1 or later (the "LGPL"),
 * in which case the provisions of the GPL or the LGPL are applicable instead
 * of those above. If you wish to allow use of your version of this file only
 * under the terms of either the GPL or the LGPL, and not to allow others to
 * use your version of this file under the terms of the MPL, indicate your
 * decision by deleting the provisions above and replace them with the notice
 * and other provisions required by the GPL or the LGPL. If you do not delete
 * the provisions above, a recipient may use your version of this file under
 * the terms of any one of the MPL, the GPL or the LGPL.
 *
 * ***** END LICENSE BLOCK ***** *)

interface

{.$define ASMVersion}

function SuperFastHash(AData: pointer; ADataLength: Integer): Cardinal;
function SuperFastHashLargeData(AData: pointer; ADataLength: Integer): Cardinal;

implementation

// Pascal translation of the SuperFastHash function by Paul Hsieh
// more info: http://www.azillionmonkeys.com/qed/hash.html
function SuperFastHash(AData: pointer; ADataLength: Integer): Cardinal;
{$ifndef ASMVersion}
var
  TempPart: Cardinal;
  RemainingBytes: Integer;
  RemainingDWords: Integer;
begin
  if not Assigned(AData) or (ADataLength <= 0) then
  begin
    Result := 0;
    Exit;
  end;
  Result := ADataLength;
  RemainingBytes := ADataLength and 3; // mod 4
  RemainingDWords := ADataLength shr 2; // div 4

  // main loop
  while RemainingDWords > 0 do
  begin
    Result := Result + PWord(AData)^;
    // splitting the pointer math keeps the amount of registers pushed at 2
    AData  := Pointer(Cardinal(AData) + SizeOf(Word));
    TempPart := (PWord(AData)^ shl 11) xor Result;
    Result := (Result shl 16) xor TempPart;
    AData  := Pointer(Cardinal(AData) + SizeOf(Word));
    Result := Result + (Result shr 11);
    dec(RemainingDWords);
  end;
  // Handle end cases
  if RemainingBytes = 3 then
  begin
    Result := Result +    PWord(AData)^;
    Result := Result xor (Result shl 16);
    AData  := Pointer(Cardinal(AData) + SizeOf(Word));   // skip to the last byte
    Result := Result xor ((PByte(AData)^ shl 18));
    Result := Result +   (Result shr 11);
  end
  else if RemainingBytes = 2 then
  begin
    Result := Result +    PWord(AData)^;
    Result := Result xor (Result shl 11);
    Result := Result +   (Result shr 17);
  end
  else if RemainingBytes = 1 then
  begin
    Result := Result +    PByte(AData)^;
    Result := Result xor (Result shl 10);
    Result := Result +   (Result shr 1);
  end;
  // Force "avalanching" of final 127 bits
  Result := Result xor (Result shl 3);
  Result := Result +   (Result shr 5);
  Result := Result xor (Result shl 4);
  Result := Result +   (Result shr 17);
  Result := Result xor (Result shl 25);
  Result := Result +   (Result shr 6);
{$else}
asm
    push  esi
    push  edi
    test  eax, eax // data
    jz    @Ret // eax is result
    xchg  edx, eax // swith data and length
    test  eax, eax // length, and hash
    jle    @Ret
@Start:
    mov   edi, eax
    mov   esi, eax
    and   edi, 3    // last few bytes
    shr   esi, 2    // number of DWORD loops
    jz    @Last3
@Loop:
    movzx ecx, word ptr [edx]
    add   eax, ecx
    movzx ecx, word ptr [edx + 2]

    shl   ecx, 11
    xor   ecx, eax
    shl   eax, 16

    xor   eax, ecx
    mov   ecx, eax

    shr   eax, 11
    add   eax, ecx
    add   edx, 4
    dec   esi
    jnz   @Loop
@Last3:
    test  edi, edi
    jz    @Done
    dec   edi
    jz    @OneLeft
    dec   edi
    jz    @TwoLeft

    movzx ecx, word ptr [edx]
    add   eax, ecx
    mov   ecx, eax
    shl   eax, 16
    xor   eax, ecx
    movsx ecx, byte ptr [edx + 2]
    shl   ecx, 18
    xor   eax, ecx
    mov   ecx, eax
    shr   ecx, 11
    add   eax, ecx
    jmp   @Done
@TwoLeft:
    movzx ecx, word ptr [edx]
    add   eax, ecx
    mov   ecx, eax
    shl   eax, 11
    xor   eax, ecx
    mov   ecx, eax
    shr   eax, 17
    add   eax, ecx
    jmp   @Done
@OneLeft:
    movsx ecx, byte ptr [edx]
    add   eax, ecx
    mov   ecx, eax
    shl   eax, 10
    xor   eax, ecx
    mov   ecx, eax
    shr   eax, 1
    add   eax, ecx
@Done:
    // avalanche
    mov   ecx, eax
    shl   eax, 3
    xor   eax, ecx

    mov   ecx, eax
    shr   eax, 5
    add   eax, ecx

    mov   ecx, eax
    shl   eax, 4
    xor   eax, ecx

    mov   ecx, eax
    shr   eax, 17
    add   eax, ecx

    mov   ecx, eax
    shl   eax, 25
    xor   eax, ecx

    mov   ecx, eax
    shr   eax, 6
    add   eax, ecx
@Ret:
    pop   edi
    pop   esi
    ret
{$endif}
end;

function SuperFastHashLargeData(AData: pointer; ADataLength: Integer): Cardinal;
{$ifndef ASMVersion}
type
  TWordArray = array[0..(MaxInt div SizeOf(Word)) - 1] of Word;
  PWordArray = ^TWordArray;
var
  TempPart: Cardinal;
  RemainingBytes: Integer;
  RemainingDWords: Integer;
begin
  if not Assigned(AData) or (ADataLength <= 0) then
  begin
    Result := 0;
    Exit;
  end;
  Result := ADataLength;
  RemainingBytes := ADataLength and 3;
  RemainingDWords := ADataLength shr 2; // div 4
  // large loop
  while RemainingDWords >= 4 do
  begin
    Result := Result + PWord(AData)^;
    TempPart := (PWordArray(AData)^[1] shl 11) xor Result;
    Result := (Result shl 16) xor TempPart;
    Result := Result + (Result shr 11);

    Result := Result + PWordArray(AData)^[2];
    TempPart := (PWordArray(AData)^[3] shl 11) xor Result;
    Result := (Result shl 16) xor TempPart;
    Result := Result + (Result shr 11);

    Result := Result + PWordArray(AData)^[4];
    TempPart := (PWordArray(AData)^[5] shl 11) xor Result;
    Result := (Result shl 16) xor TempPart;
    Result := Result + (Result shr 11);

    Result := Result + PWordArray(AData)^[6];
    TempPart := (PWordArray(AData)^[7] shl 11) xor Result;
    Result := (Result shl 16) xor TempPart;
    Result := Result + (Result shr 11);

    // update the pointer and the counter
    AData  := Pointer(Cardinal(AData) + (8 * SizeOf(Word)));
    RemainingDWords := RemainingDWords - 4;
  end;
  // small loop
  while RemainingDWords > 0 do
  begin
    Result := Result + PWord(AData)^;
    AData  := Pointer(Cardinal(AData) + SizeOf(Word));
    TempPart := (PWord(AData)^ shl 11) xor Result;
    Result := (Result shl 16) xor TempPart;
    AData  := Pointer(Cardinal(AData) + SizeOf(Word));
    Result := Result + (Result shr 11);
    dec(RemainingDWords);
  end;
  // Handle end cases
  if RemainingBytes = 3 then
  begin
    Result := Result +    PWord(AData)^;
    Result := Result xor (Result shl 16);
    AData  := Pointer(Cardinal(AData) + SizeOf(Word));   // skip to the last byte
    Result := Result xor ((PByte(AData)^ shl 18));
    Result := Result +   (Result shr 11);
  end
  else if RemainingBytes = 2 then
  begin
    Result := Result +    PWord(AData)^;
    Result := Result xor (Result shl 11);
    Result := Result +   (Result shr 17);
  end
  else if RemainingBytes = 1 then
  begin
    Result := Result +    PByte(AData)^;
    Result := Result xor (Result shl 10);
    Result := Result +   (Result shr 1);
  end;
    // Force "avalanching" of final 127 bits
  Result := Result xor (Result shl 3);
  Result := Result +   (Result shr 5);
  Result := Result xor (Result shl 4);
  Result := Result +   (Result shr 17);
  Result := Result xor (Result shl 25);
  Result := Result +   (Result shr 6);
{$else}
 asm
    push  esi
    push  edi
    test  eax, eax // test for nil pointer
    jz    @Ret     // eax is also result, so save ret here
    xchg  edx, eax // swith data and length
    test  eax, eax // length, and hash
    jle    @Ret
@Start:
    mov   edi, eax
    mov   esi, eax
    and   edi, 3    // last few bytes
    shr   esi, 2    // number of DWORD loops
    jz    @Last3
@LargeLoop:
    cmp esi,$04
    jl @Loop
    // first DWORD
    movzx ecx, word ptr [edx]
    add   eax, ecx
    movzx ecx, word ptr [edx + 2]

    shl   ecx, 11
    xor   ecx, eax
    shl   eax, 16

    xor   eax, ecx
    mov   ecx, eax

    shr   eax, 11
    add   eax, ecx
    // second DWORD
    movzx ecx, word ptr [edx + 4]
    add   eax, ecx
    movzx ecx, word ptr [edx + 6]

    shl   ecx, 11
    xor   ecx, eax
    shl   eax, 16

    xor   eax, ecx
    mov   ecx, eax

    shr   eax, 11
    add   eax, ecx

    // third DWORD
    movzx ecx, word ptr [edx + 8]
    add   eax, ecx
    movzx ecx, word ptr [edx + 10]

    shl   ecx, 11
    xor   ecx, eax
    shl   eax, 16

    xor   eax, ecx
    mov   ecx, eax

    shr   eax, 11
    add   eax, ecx

    // fourth DWORD
    movzx ecx, word ptr [edx + 12]
    add   eax, ecx
    movzx ecx, word ptr [edx + 14]

    shl   ecx, 11
    xor   ecx, eax
    shl   eax, 16

    xor   eax, ecx
    mov   ecx, eax

    shr   eax, 11
    add   eax, ecx

    add   edx, 16
    sub   esi, 4
    jz    @Last3
    jmp   @LargeLoop
@Loop:
    movzx ecx, word ptr [edx]
    add   eax, ecx
    movzx ecx, word ptr [edx + 2]

    shl   ecx, 11
    xor   ecx, eax
    shl   eax, 16

    xor   eax, ecx
    mov   ecx, eax

    shr   eax, 11
    add   eax, ecx
    add   edx, 4
    dec   esi
    jnz   @Loop
@Last3:
    test  edi, edi
    jz    @Done
    dec   edi
    jz    @OneLeft
    dec   edi
    jz    @TwoLeft

    movzx ecx, word ptr [edx]
    add   eax, ecx
    mov   ecx, eax
    shl   eax, 16
    xor   eax, ecx
    movsx ecx, byte ptr [edx + 2]
    shl   ecx, 18
    xor   eax, ecx
    mov   ecx, eax
    shr   ecx, 11
    add   eax, ecx
    jmp   @Done
@TwoLeft:
    movzx ecx, word ptr [edx]
    add   eax, ecx
    mov   ecx, eax
    shl   eax, 11
    xor   eax, ecx
    mov   ecx, eax
    shr   eax, 17
    add   eax, ecx
    jmp   @Done
@OneLeft:
    movsx ecx, byte ptr [edx]
    add   eax, ecx
    mov   ecx, eax
    shl   eax, 10
    xor   eax, ecx
    mov   ecx, eax
    shr   eax, 1
    add   eax, ecx
@Done:
    // avalanche
    mov   ecx, eax
    shl   eax, 3
    xor   eax, ecx

    mov   ecx, eax
    shr   eax, 5
    add   eax, ecx

    mov   ecx, eax
    shl   eax, 4
    xor   eax, ecx

    mov   ecx, eax
    shr   eax, 17
    add   eax, ecx

    mov   ecx, eax
    shl   eax, 25
    xor   eax, ecx

    mov   ecx, eax
    shr   eax, 6
    add   eax, ecx
@Ret:
    pop   edi
    pop   esi
    ret
{$endif}
end;

end.
