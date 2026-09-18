class_name SkillData
extends Resource
## 技能静态数据（主动 / 支援 / 被动）

enum Kind { ACTIVE, SUPPORT, PASSIVE }

@export var id: String = ""                          ## UUID（D-4）
@export var display_name: String = ""                ## 如「鼓舞」「蜂王巢口」
@export var kind: Kind = Kind.ACTIVE
@export var glossary: String = ""                    ## 前缀标记，如「机场」「指令」
@export var description: String = ""                 ## 技能描述（详情区文本）
@export var target_range: int = 0                    ## 施放距离（格）
@export var affects_enemies: bool = false            ## 目标阵营
@export var ends_actor_action: bool = false          ## 使用后结束该单位行动
@export var effects: Array[EffectData] = []          ## 施加的效果


func validate() -> Array[String]:
	var errs: Array[String] = []
	if id == "" or not Uuid.is_valid(id):
		errs.append("SkillData[%s] id 非 UUID：%s" % [display_name, id])
	if display_name == "":
		errs.append("SkillData[%s] display_name 为空" % id)
	for e in effects:
		if e == null:
			errs.append("SkillData[%s] effects 含 null" % display_name)
		elif (e as EffectData).id == "":
			errs.append("SkillData[%s] 引用的 EffectData 缺 id" % display_name)
	return errs
