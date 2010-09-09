:- module(skosmatcher,
	  [skos_find_candidates/3 % +SourceConcept, +TargetScheme, +Options, -Results
	  ]
	 ).

:- use_module(library(semweb/rdf_db)).
:- use_module(amalgame(mappings/edoal)).
:- use_module(levenshtein).

%%	skos_find_candidates(+C, +S, +Options, -Result) is det.
%
%	Return all correspondences candidates for for SKOS concept C
%	from SKOS scheme S. Result is an RDF graph in (extended) EDOAL format
%
%	Options include:
%	- labels_must_match(true):
%           Find candidates with match labels (cheap)

skos_find_candidates(SourceConcept, TargetConceptScheme, Options):-
	forall(candidate(SourceConcept, TargetConceptScheme, Options),
	       true
	      ).

%%	candidate(+C, +S, +Options) is det.
%
%	Asserts a correspondence as an EDOAL cell
%	describing a match from C to a target concept from
%	ConceptScheme S.
%
%       Correspondence has a low confidence level,
%       to indicate that further checking will be needed to
%       evaluate the quality of this candidate.
%
%       The method will list which (pref/alt) labels properties
%       where used for the match.
%
%       For descriptions of possible Options, see above.

candidate(SourceConcept, TargetConceptScheme, Options) :-
	ground(SourceConcept),
	ground(TargetConceptScheme),
	ground(Options),
	option(candidate_matchers(Matchers), Options, []),
	memberchk(labelmatch, Matchers),
	rdf_has(SourceConcept, rdfs:label, literal(lang(_, Label)), RealLabel1Predicate),
	rdf_has(TargetConcept, rdfs:label, literal(lang(_, Label)), RealLabel2Predicate),
	rdf_has(TargetConcept, skos:inScheme, TargetConceptScheme),
	format(atom(Method), 'exact match: ~p-~p', [RealLabel1Predicate, RealLabel2Predicate]),
	CellOptions = [measure(0.001), % Only label match, this is just a candidate
		       method(Method)
		       |Options
		      ],
	assert_cell(SourceConcept, TargetConcept, CellOptions).



%	These versions match only the language specific labels (passed
%	through option language(Lan). It is not case sensitive The
%	first one takes into consideration that the prefLabel can have a
%	blanknode with rdf:value "literal(...)". This is the case in
%	ASFA


candidate(SourceConcept, TargetConceptScheme, Options) :-
	ground(SourceConcept),
	ground(TargetConceptScheme),
	ground(Options),
	option(candidate_matchers(Matchers), Options, []),
	option(language(Lan),Options,[]),
	memberchk(labelmatchEN, Matchers),
	rdf_has(SourceConcept, rdfs:label, literal(lang(Lan, Label)), RealLabel1Predicate),
	rdf_has(TargetConceptBN, rdf:value, literal(exact(Label),lang(en, _RealLabel))),
       	rdf_has(TargetConcept, rdfs:label, TargetConceptBN, RealLabel2Predicate),
	rdf_has(TargetConcept, skos:inScheme, TargetConceptScheme),
	format(atom(Method), 'exact EN match: ~p-~p', [RealLabel1Predicate, RealLabel2Predicate]),
	CellOptions = [measure(0.001), % Only label match, this is just a candidate
		       method(Method)
		       |Options
		      ],
	assert_cell(SourceConcept, TargetConcept, CellOptions).

candidate(SourceConcept, TargetConceptScheme, Options) :-
	ground(SourceConcept),
	ground(TargetConceptScheme),
	ground(Options),
	option(candidate_matchers(Matchers), Options, []),
	option(language(Lan),Options,[]),
	memberchk(labelmatchEN, Matchers),
	rdf_has(SourceConcept, rdfs:label, literal(lang(Lan, Label)), RealLabel1Predicate),
	rdf_has(TargetConcept, rdfs:label, literal(exact(Label),lang(_, _RealLabel)), RealLabel2Predicate),
	rdf_has(TargetConcept, skos:inScheme, TargetConceptScheme),
	format(atom(Method), 'exact EN match: ~p-~p', [RealLabel1Predicate, RealLabel2Predicate]),
	CellOptions = [measure(0.001), % Only label match, this is just a candidate
		       method(Method)
		       |Options
		      ],
	assert_cell(SourceConcept, TargetConcept, CellOptions).




% This version of candidate/3 asserts a match when the
% Levenshtein distance between two labels is less than a maximum
% (retrieved from stringdist_setting/2). For reasons of scalability,
% only labels with a common prefix of a certain length (also a parameter
% retrieved from stringdist_setting/2) are considered.
% Here, a confidence of 0.0005 is used.

candidate(SourceConcept, TargetConceptScheme, Options) :-
	ground(SourceConcept),
	ground(TargetConceptScheme),
	ground(Options),
	option(candidate_matchers(Matchers), Options, []),
	memberchk(stringdist, Matchers),
       	write('.'),flush,
	rdf_has(TargetConcept, skos:inScheme, TargetConceptScheme),
	rdf_has(SourceConcept, rdfs:label, literal(lang(_, Label1)), RealLabel1Predicate),
	stringdist_setting(prefixdepth,PrefLen),
	sub_atom(Label1,0,PrefLen,_,Prefix),
	rdf_has(TargetConcept, rdfs:label, literal(prefix(Prefix), Label2), RealLabel2Predicate),
	%rdf_has(TargetConcept, rdfs:label, literal(lang(_, Label2)), RealLabel2Predicate),
	max_stringdist(Label1, Label2, 1),
	format(atom(Method), 'stringdist match: ~p-~p', [RealLabel1Predicate, RealLabel2Predicate]),
	CellOptions = [measure(0.0001), % Only label match, this is just a candidate
		       method(Method)
		       |Options
		      ],
	assert_cell(SourceConcept, TargetConcept, CellOptions).


stringdist_setting(prefixdepth,2).
stringdist_setting(maxlevdist,2).

% succeeds if Label1 and Label2 have a levenshtein distance of
% Maxdist or less after a normalization step where whitespaces and
% punctuation is removed.

max_stringdist(Label1, Label2, MaxDist):-
	labnorm(Label1, L1N),
      	labnorm(Label2, L2N),
	levenshtein(L1N,L2N,Dist),!,
	Dist =< MaxDist,!.

max_stringdist(Label1, Label2, _MaxDist):-
	Label1 = Label2.

labnorm(L,LN):-
	downcase_atom(L, LD),
	atom_chars(LD, LC),
	delete(LC, ' ',  LC1),
	delete(LC1, ',',  LC2),
	delete(LC2, '.',  LC3),
	delete(LC3, '-',  Lchars),
	atom_chars(LN,Lchars),!.
