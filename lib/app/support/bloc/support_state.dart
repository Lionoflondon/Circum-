part of 'support_bloc.dart';

abstract class SupportState extends Equatable {
  const SupportState();
  
  @override
  List<Object> get props => [];
}

class SupportInitial extends SupportState {}
