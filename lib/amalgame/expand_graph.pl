:- module(expand_graph,
	  [ expand_mapping/2,
	    expand_vocab/2,
 	    flush_expand_cache/0,
	    flush_expand_cache/1,     % +Id
	    process_options/3
	  ]).

:- use_module(library(semweb/rdf_db)).
:- use_module(library(semweb/rdfs)).
:- use_module(library(http/http_parameters)).
:- use_module(library(amalgame/amalgame_modules)).
:- use_module(library(amalgame/map)).

:- dynamic
	expand_cache/2.

:- setting(cache_time, float, 0.5,
	   'Minimum execution time to cache results').

%%	expand_mapping(+Id, -Result) is det.
%
%	Generate the Result corresponding to Id.
%	We use a mutex so that the next thread will use the cached
%	version.
%
%	@param Id
%          if Id is a Mapping Result is [align(c1,c2,prov)]
%          if Id is a Vocabulary Result is an assoc or one of
%          scheme(Scheme) or type(Class)

expand_mapping(Id, Mapping) :-
	rdf_has(Id, opmv:wasGeneratedBy, Process, OutputType),
	with_mutex(Id, expand_process(Process, Result)),
    	select_result_mapping(Result, OutputType, Mapping),
	length(Mapping, Count),
	debug(ag_expand, 'Found ~w mappings for ~p', [Count, Id]),
	materialize_if_needed(Id, Mapping).

%%	expand_vocab(+Id, -Concepts) is det.
%
%	Generate the Vocab.
%	@param Id is URI of a conceptscheme or an identifier for a set
%	of concepts derived by a vocabulary process,

expand_vocab(Id, Vocab) :-
	rdf_has(Id, opmv:wasGeneratedBy, Process),
	!,
 	expand_process(Process, Vocab).
expand_vocab(Vocab, Vocab) :-
	rdf(Vocab, rdf:type, skos:'ConceptScheme'),
	!.


%%	expand_process(+Process, -Result)
%
%	Expand process to generate Result
%
%	Results are cached when execution time eof process takes longer
%	then setting(cache_time).

expand_process(Process, Result) :-
	ground(Process),
	expand_cache(Process, Result),
	!,
	debug(ag_expand, 'Output of process ~p taken from cache', [Process]).
expand_process(Process, Result) :-
	!,
	rdf(Process, rdf:type, Type),
	amalgame_module_id(Type, Module),
	process_options(Process, Module, Options),
 	exec_amalgame_process(Type, Process, Module, Result, Time, Options),
	cache_expand_result(Time, Process, Result),
	debug(ag_expand, 'Output of process ~p (~p) computed in ~ws',
	      [Process,Type,Time]).

cache_expand_result(ExecTime, Process, Result) :-
	setting(cache_time, CacheTime),
 	ExecTime > CacheTime,
	!,
	assert(expand_cache(Process, Result)).
cache_expand_result(_, _, _).

%%	flush_expand_cache(+Id)
%
%	Retract all cached mappings.

flush_expand_cache :-
	flush_expand_cache(_).
flush_expand_cache(Id) :-
	retractall(expand_cache(Id, _)).


%%	exec_amalgame_process(+Type, +Process, +Module, -Result,
%%	+Options)
%
%	Result is generated by executing Process of type Type.
%
%	@error existence_error(mapping_process)

exec_amalgame_process(Type, Process, Module, Mapping, Time, Options) :-
	rdfs_subclass_of(Type, amalgame:'Matcher'),
	!,
 	(   rdf(Process, amalgame:source, SourceId),
	    rdf(Process, amalgame:target, TargetId)
	->  expand_vocab(SourceId, Source),
	    expand_vocab(TargetId, Target),
	    timed_call(Module:matcher(Source, Target, Mapping0, Options), Time)
	;   rdf(Process, amalgame:input, InputId),
	    expand_mapping(InputId, MappingIn),
	    timed_call(Module:filter(MappingIn, Mapping0, Options), Time)
	),
 	merge_provenance(Mapping0, Mapping).
exec_amalgame_process(Class, Process, Module, Result, Time, Options) :-
	rdfs_subclass_of(Class, amalgame:'VocExclude'),
	!,
  	rdf(Process, amalgame:input, Input),
	expand_vocab(Input, Vocab),
	findall(S, rdf(Process, amalgame:exclude, S), Ss),
	maplist(expand_mapping, Ss, Expanded),
	append(Expanded, Mapping),
  	timed_call(Module:exclude(Vocab, Mapping, Result, Options), Time).
exec_amalgame_process(Class, Process, Module, Result, Time, Options) :-
	rdfs_subclass_of(Class, amalgame:'MappingSelecter'),
	!,
	Result = select(Selected, Discarded, Undecided),
 	rdf(Process, amalgame:input, InputId),
	expand_mapping(InputId, MappingIn),
  	timed_call(Module:selecter(MappingIn, Selected, Discarded, Undecided, Options), Time).
exec_amalgame_process(Class, Process, Module, Result, Time, Options) :-
	rdfs_subclass_of(Class, amalgame:'VocabSelecter'),
	!,
  	rdf(Process, amalgame:input, Input),
	expand_vocab(Input, Vocab),
  	timed_call(Module:selecter(Vocab, Result, Options), Time).
exec_amalgame_process(Class, Process, Module, Result, Time, Options) :-
	rdfs_subclass_of(Class, amalgame:'Merger'),
	!,
	findall(Input, rdf(Process, amalgame:input, Input), Inputs),
	maplist(expand_mapping, Inputs, Expanded),
	timed_call(Module:merger(Expanded, Result, Options), Time).
exec_amalgame_process(Class, Process, _, _, _, _) :-
	throw(error(existence_error(mapping_process, [Class, Process]), _)).

timed_call(Goal, Time) :-
	thread_self(Me),
        thread_statistics(Me, cputime, T0),
	call(Goal),
	thread_statistics(Me, cputime, T1),
        Time is T1 - T0.


%%	select_result_mapping(+ProcessResult, +OutputType, -Mapping)
%
%	Mapping is part of ProcessResult as defined by OutputType.
%
%	@param OutputType is an RDF property
%	@error existence_error(mapping_select)

select_result_mapping(select(Selected, Discarded, Undecided), OutputType, Mapping) :-
	!,
	(   rdf_equal(amalgame:selectedBy, OutputType)
	->  Mapping = Selected
	;   rdf_equal(amalgame:discardedBy, OutputType)
	->  Mapping = Discarded
	;   rdf_equal(amalgame:untouchedBy, OutputType)
	->  Mapping = Undecided
	;   throw(error(existence_error(mapping_selector, OutputType), _))
	).
select_result_mapping(Mapping, P, Mapping) :-
	is_list(Mapping),
	rdf_equal(opmv:wasGeneratedBy, P).

%%	process_options(+Process, +Module, -Options)
%
%	Options are the instantiated parameters for Module based on the
%	parameters string in Process.

process_options(Process, Module, Options) :-
	rdf(Process, amalgame:parameters, literal(ParamString)),
 	!,
	module_options(Module, Options, Parameters),
	parse_url_search(ParamString, Search),
	Request = [search(Search)] ,
	http_parameters(Request, Parameters).
process_options(_, _, []).


%%	module_options(+Module, -Options, -Parameters)
%
%	Options  are  all  option  clauses    defined   for  Module.
%	Parameters is a specification list for http_parameters/3.
%	Module:parameter is called as:
%
%	    parameter(Name, Properties, Description)
%
%	Name is the name of the	the option, The Properties are as
%	supported by http_parameters/3.	Description is used by the help
%	system.

module_options(Module, Options, Parameters) :-
	current_predicate(Module:parameter/4),
	!,
	findall(O-P,
		( call(Module:parameter, Name, Type, Default, _Description),
		  O =.. [Name, Value],
		  param_options(Type, Default, ParamOptions),
		  P =.. [Name, Value, ParamOptions]
		),
		Pairs),
	pairs_keys_values(Pairs, Options, Parameters).
module_options(_, _, []).


param_options(Type, Default, Options) :-
	(   is_list(Type)
	->  Options = [default(Default)|Type]
	;   Options = [default(Default), Type]
	).

%%	materialize_if_needed(+Id, Mapping) is det.
%
%	materialize result in Mapping in named graph Id if this graph
%	this graph does not exist yet and if the resource with the same
%	Id has the amalgame:status amalgame:final.

materialize_if_needed(Id, Mapping) :-
	(   \+ rdf_graph(Id), rdf_has(Id, amalgame:status, amalgame:final)
	->  materialize_mapping_graph(Mapping, [graph(Id)])
	;   true
	).
