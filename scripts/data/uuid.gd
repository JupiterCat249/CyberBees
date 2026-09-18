class_name Uuid
extends RefCounted
## UUID v4 生成 / 校验（D-4：资源 id 一律 UUID 化，确保每个单位/卡牌有独立 ID）
##
## 实现说明（为什么先用 GDScript 而非 GDExtension）：
##   Godot 4.7 内置 `Crypto.generate_random_bytes()`（底层由引擎的加密模块提供，
##   在 Windows 上走 BCryptGenRandom，属操作系统级 CSPRNG），
##   用 16 字节随机数按 RFC 4122 §4.4 手工编排 v4 版本位与 variant 位，
##   得到的字符串即标准 UUIDv4（无需第三方库）。
##   若日后需要"从字符串派生 UUID"（v3/v5，MD5/SHA-1）等能力，
##   再按 D-4 建议引入 GDExtension（C++）扩展；当前 UUIDv4 不需要。

const _HEX := "0123456789abcdef"

## 生成一个标准 UUIDv4 字符串（小写，带连字符）
static func generate() -> String:
	var crypto := Crypto.new()
	var b := crypto.generate_random_bytes(16)
	# RFC 4122：version = 4（高 4 位），variant = 10xx
	b[6] = (b[6] & 0x0F) | 0x40
	b[8] = (b[8] & 0x3F) | 0x80
	var s := ""
	for i in 16:
		s += _HEX[(b[i] >> 4) & 0x0F]
		s += _HEX[b[i] & 0x0F]
		if i == 3 or i == 5 or i == 7 or i == 9:
			s += "-"
	return s

## 严格校验：8-4-4-4-12 且全为十六进制字符
static func is_valid(u: String) -> bool:
	if u.length() != 36:
		return false
	for i in 36:
		var c := u[i]
		if i == 8 or i == 13 or i == 18 or i == 23:
			if c != "-":
				return false
		elif not (("0" <= c and c <= "9") or ("a" <= c and c <= "f") or ("A" <= c and c <= "F")):
			return false
	return true

## 是 v4 吗（第 13 位为 4）
static func is_v4(u: String) -> bool:
	return is_valid(u) and u[14] == "4"

## 空则生成、非空则原样返回（用于"缺 id 时补一个稳定值"的兜底）
static func ensure(u: String) -> String:
	return u if is_valid(u) else generate()
