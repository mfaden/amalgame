:- module(vocab,
	  [ vocab_member/2
	  ]).

:- use_module(library(semweb/rdf_db)).
:- use_module(library(semweb/rdfs)).
:- use_module(voc_stats).
:- use_module(expand_graph). % for virtual vocab schemes

%%	vocab_member(?C, +VocabDef)
%
%	True if C is part of Vocabulary.
%
%	@param VocabDef is a URI of a skos:ConceptScheme or a definition
%	of a subset thereof.

vocab_member(C, vocspec(Spec)) :-
	!,
	vocab_member(C, Spec).
vocab_member(C, not(Def)) :-
	ground(C),
	ground(Def),
	\+ vocab_member(C, Def).
vocab_member(E, and(G1,G2)) :-
	!,
	vocab_member(E,G1),
	vocab_member(E,G2).

vocab_member(E, alignable(Alignable)) :-
	rdf(Alignable, amalgame:class, Class),
	rdf(Alignable, amalgame:graph, Graph),
	!,
	vocab_member(E, graph(Graph)),
	vocab_member(E, type(Class)).

vocab_member(E, scheme(Scheme)) :-
	(   voc_property(Scheme, virtual(false))
	->  vocab_member(E, rscheme(Scheme))
	;   vocab_member(E, vscheme(Scheme))
	).


vocab_member(E, vscheme(Scheme)) :-
	rdf(Scheme, amalgame:wasGeneratedBy, _, Strategy),
	rdfs_individual_of(Strategy, amalgame:'AlignmentStrategy'),
	expand_node(Strategy, Scheme, VocSpec),
	!,
	vocab_member(E, VocSpec).

vocab_member(E, rscheme(Scheme)) :-
	rdf_has(E, skos:inScheme, Scheme).

vocab_member(E, type(Class)) :-
	!,
	rdfs_individual_of(E, Class).
vocab_member(E, graph(G)) :-
	!,
	rdf(E, rdf:type, _, G).
vocab_member(E, propvalue(any, Value)) :- !,
	rdf(E, _Property, Value).
vocab_member(E, propvalue(Property, any)) :- !,
	rdf(E, Property, _Value).
vocab_member(E, propvalue(Property, Value)) :- !,
	rdf(E, Property, Value).
vocab_member(E, subtree(Root)) :-
	!,
	rdf_reachable(E, skos:broader, Root).
vocab_member(F, 'http://sws.geonames.org/') :-
	!,
	rdfs_individual_of(F, 'http://www.geonames.org/ontology#Feature').
vocab_member(E, Scheme) :-
	atom(Scheme),
	rdfs_individual_of(Scheme, skos:'ConceptScheme'),
	!,
	vocab_member(E, scheme(Scheme)).

vocab_member(E, Scheme) :-
	atom(Scheme),
	rdfs_individual_of(Scheme, amalgame:'Alignable'),
	!,
	vocab_member(E, alignable(Scheme)).

/*
vocab_member(I, EDMGraph) :-
	atom(EDMGraph),
	rdf(_, 'http://www.europeana.eu/schemas/edm/country',_, EDMGraph),
	!,
	rdf(I, 'http://www.europeana.eu/schemas/edm/country', _, EDMGraph).
*/
vocab_member(E, Class) :-
	atom(Class),
	rdfs_individual_of(Class, rdfs:'Class'),
	!,
	rdfs_individual_of(E, Class).



