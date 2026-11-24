// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'card_item.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CardItemAdapter extends TypeAdapter<CardItem> {
  @override
  final int typeId = 0;

  @override
  CardItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    final typeIndex = fields[5] as int?;
    final stateIndex = fields[7] as int?;
    return CardItem(
      frontText: fields[0] as String,
      backText: fields[1] as String,
      collectionId: fields[2] as String,
      createdAt: fields[3] as DateTime?,
      id: fields[4] as String?,
      type: CardType.fromIndex(typeIndex),
      tags: (fields[6] as List?)?.cast<String>() ?? const [],
      state: CardLearningState.fromIndex(stateIndex),
      step: fields[8] as int?,
      stability: (fields[9] as num?)?.toDouble(),
      difficulty: (fields[10] as num?)?.toDouble(),
      due: fields[11] as DateTime?,
      lastReview: fields[12] as DateTime?,
      reps: fields[13] as int? ?? 0,
      lapses: fields[14] as int? ?? 0,
      updatedAt: fields[15] as DateTime?,
      imagePath: fields[16] as String?,
      audioPath: fields[17] as String?,
      noteId: fields[18] as String?,
      reverse: fields[19] as bool? ?? false,
      clozeIndex: fields[20] as int? ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, CardItem obj) {
    writer
      ..writeByte(21)
      ..writeByte(0)
      ..write(obj.frontText)
      ..writeByte(1)
      ..write(obj.backText)
      ..writeByte(2)
      ..write(obj.collectionId)
      ..writeByte(3)
      ..write(obj.createdAt)
      ..writeByte(4)
      ..write(obj.id)
      ..writeByte(5)
      ..write(obj.type.index)
      ..writeByte(6)
      ..write(obj.tags)
      ..writeByte(7)
      ..write(obj.state.index)
      ..writeByte(8)
      ..write(obj.step)
      ..writeByte(9)
      ..write(obj.stability)
      ..writeByte(10)
      ..write(obj.difficulty)
      ..writeByte(11)
      ..write(obj.due)
      ..writeByte(12)
      ..write(obj.lastReview)
      ..writeByte(13)
      ..write(obj.reps)
      ..writeByte(14)
      ..write(obj.lapses)
      ..writeByte(15)
      ..write(obj.updatedAt)
      ..writeByte(16)
      ..write(obj.imagePath)
      ..writeByte(17)
      ..write(obj.audioPath)
      ..writeByte(18)
      ..write(obj.noteId)
      ..writeByte(19)
      ..write(obj.reverse)
      ..writeByte(20)
      ..write(obj.clozeIndex);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CardItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
