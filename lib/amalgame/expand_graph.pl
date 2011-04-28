:- module(expand_graph,
	  [ expand_mapping/2,
	    expand_vocab/2,
	    flush_mapping_cache/0,
	    flush_mapping_cache/1     % +Id
	  ]).

:- use_module(library(semweb/rdf_db)).
:- use_module(library(semweb/rdfs)).
:- use_module(library(http/http_parameters)).
:- use_module(library(amalgame/amalgame_modules)).

:- dynamic
	mapping_cache/2.


%%	expand_mapping(+Id, -Mapping:[align(s,t,prov)]) is det.
%
%	Generate the Mapping. Caching is used for the results of
%	matchers.
%
%	@param Id is a URI of Mapping

expand_mapping(Id, Mapping) :-
	mapping_cache(Id, Mapping),
	!,
	debug_mapping_expand(cache, Id, Mapping).
expand_mapping(Id, Mapping) :-
	rdf_has(Id, opmv:wasGeneratedBy, Process, OutputType),
	rdf(Process, rdf:type, URI),
	amalgame_module_id(Class, URI, Module),
	process_options(Process, Module, Options),
	exec_mapping_process(Class, Process, Module, Results, Options),
	cache_mapping_result(Class, Results, Id),
 	select_result_mapping(Results, OutputType, Mapping),
	debug_mapping_expand(Process, Id, Mapping).

debug_mapping_expand(Process, Id, Mapping) :-
	debug(ag_expand),
	!,
	length(Mapping, Count),
	(   Process == cache
	->  debug(ag_expand, 'Mapping ~p (~w) taken from cache',
	      [Id, Count])
	;   debug(ag_expand, 'Mapping ~p (~w) generated by process ~p',
	      [Id, Process, Count])
	).
debug_mapping_expand(_, _, _).


cache_mapping_result(Class, Mapping, Id) :-
	rdfs_subclass_of(Class, amalgame:'Matcher'),
	!,
	assert(mapping_cache(Id, Mapping)).
cache_mapping_result(_, _, _).

%%	flush_mapping_cache(+Id)
%
%	Retract all cached mappings.

flush_mapping_cache :-
	flush_mapping_cache(_).
flush_mapping_cache(Id) :-
	retractall(mapping_cache(Id, _)).

%%	expand_vocab(+Id, -Concepts) is det.
%
%	Generate the Vocab.
%	@param Id is URI of a conceptscheme or an identifier for a set
%	of concepts derived by a vocabulary process,
%
%       @TBD

expand_vocab(Id, Concepts) :-
	rdf_has(Id, opmv:wasGeneratedBy, _Process),
	!,
	Concepts = [].
expand_vocab(Id, Id).


%%	exec_mapping_process(+Class, +Process, +Module, -Mapping,
%%	+Options)
%
%	Mapping is the mapping corresponding to Id and is generated by
%	executing Process
%
%	@error existence_error(mapping_process)

exec_mapping_process(Class, Process, Module, Mapping, Options) :-
	rdfs_subclass_of(Class, amalgame:'Matcher'),
	!,
 	(   rdf(Process, amalgame:input, InputId)
	->  expand_mapping(InputId, MappingIn),
	    call(Module:filter, MappingIn, Mapping0, Options)
	;   rdf(Process, amalgame:source, SourceId),
	    rdf(Process, amalgame:target, TargetId)
	->  expand_vocab(SourceId, Source),
	    expand_vocab(TargetId, Target),
	    call(Module:matcher, Source, Target, Mapping0, Options)
	),
	merge_provenance(Mapping0, Mapping).
exec_mapping_process(Class, Process, Module, Result, Options) :-
	rdfs_subclass_of(Class, amalgame:'Selecter'),
	!,
	Result = select(Selected, Discarded, Undecided),
 	rdf(Process, amalgame:input, InputId),
	expand_mapping(InputId, MappingIn),
  	call(Module:selecter, MappingIn, Selected, Discarded, Undecided, Options).
exec_mapping_process(Class, Process, _, _, _) :-
	throw(error(existence_error(mapping_process, [Class, Process]), _)).


%%	select_result_mapping(+ProcessResult, +OutputType, -Mapping)
%
%	Mapping is part of ProcessResult as defined by OutputType.
%
%	@param OutputType is an RDF property
%	@error existence_error(mapping_select)

select_result_mapping(Mapping, P, Mapping) :-
	is_list(Mapping),
	rdf_equal(opmv:wasGeneratedBy, P),
	!.
select_result_mapping(select(Selected, Discarded, Undecided), OutputType, Mapping) :-
	!,
	(   rdf_equal(amalgame:selectedBy, OutputType)
	->  Mapping = Selected
	;   rdf_equal(amalgame:discardedBy, OutputType)
	->  Mapping = Discarded
	;   rdf_equal(amalgame:untouchedBy, OutputType)
	->  Mapping = Undecided
	).
select_result_mapping(_, OutputType, _) :-
	throw(error(existence_error(mapping_selector, OutputType), _)).

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
	findall(O-P,
		( call(Module:parameter, Name, Type, Default, _Description),
		  O =.. [Name, Value],
		  P =.. [Name, Value, [Type, default(Default)]]
		),
		Pairs),
	pairs_keys_values(Pairs, Options, Parameters).


%%	merge_provenance(+AlignIn, -AlignOut)
%
%	Collects all provenance for similar source target pairs.
%	AlignIn is a sorted list of align/3 terms.

merge_provenance([], []).
merge_provenance([align(S, T, P)|As], Gs) :-
	group_provenance(As, S, T, P, Gs).

group_provenance([align(S,T,P)|As], S, T, P0, Gs) :-
	!,
	append(P, P0, P1),
	group_provenance(As, S, T, P1, Gs).
group_provenance(As, S, T, P, [align(S, T, Psorted)|Gs]) :-
	sort(P, Psorted),
	merge_provenance(As, Gs).
