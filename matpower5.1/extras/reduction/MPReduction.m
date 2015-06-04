function [mpcreduced,Link,BCIRCr]=MPReduction(mpc,ExBusOrig,Pf_flag)
% Function MPReduction does modified Ward reduction to the full system
% model given in the MATPOWER case file (mpc) based the external buses
% (ExBusOrig)defined by the user.
%
%  [mpcreduced,Link,BCIRCr]=MPReduction(mpc,ExBusOrig,Pf_flag)
%
% INPUT DATA:
%   mpc: struct, includes the full model in MATPOWER case format
%   ExBusOrig: n*1 vector, include the bus numbers of buses to be
%   eliminated
%   Pf_flag: scalar, indicate if dc power flow needed to solve (=1) or not
%       (=0) in the load redistribution subroutine
%   
% OUTPUT DATA:
%   mpcreduced: struct, includes the reduced model in MATPOWER case format
%   Link: n*2 matrix, includes the generator mapping info, showing how
%       external generators are moved: The first column includes generator bus
%       numbers in full model and the second column includes generator bus
%       nubmers where the external generators are moved to.
%   BCIRCr: n*1 vector, includes branch circuit numbers. This vector can be
%       used to identify parallel branches and equivalent lines generated by
%       the network reduction process. If a branch number is higher than 1 and
%       less then it indicate this branch is parallel to one of the branch in
%       the full model. If a branch circuit number is 99 then it indicate this
%       branch is an equivalent branch.
%
% Note: The reduction is based on dc assumption which means all resistance,
% reactive power components will be ignored. And the reduced model is only
% good for solving dc power flow or dc opf. If the input full model case
% file includes dclines, it is assumed that no dc terminal is to be
% eliminated, otherwise the function will return error. If Pf_flag = 1
% which means dc power flow need to be solved during the load
% redistribution process, user must make sure that MATPOWER toolbox is
% installed.

%   MATPOWER
%   Copyright (c) 2014-2015 by Power System Engineering Research Center (PSERC)
%   by Yujia Zhu, PSERC ASU
%
%   $Id: MPReduction.m 2655 2015-03-18 16:40:32Z ray $
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See http://www.pserc.cornell.edu/matpower/ for more info.

fprintf('%n Reduction process start');
fprintf('%n Preprocess data')';
[mpc,ExBusOrig]=PreProcessData(mpc,ExBusOrig);
dim = size(mpc.bus,1);
%% Modeling
% check if dc terminals are external
if isfield(mpc,'dcline')
tf1 = ismember(mpc.dcline(:,1),ExBusOrig);
tf2 = ismember(mpc.dcline(:,2),ExBusOrig);
if (sum(tf1)+sum(tf2))>0
    error('not able to eliminate HVDC line terminals');
end
end
ExBusOrig = ExBusOrig';
if ~isempty(ExBusOrig)
fprintf('\nConvert input data model');
[NFROM,NTO,BraNum,LineB,ShuntB,BCIRC,BusNum,NUMB,SelfB,mpc,ExBus,newbusnum,oldbusnum] = Initiation(mpc,ExBusOrig); % ExBus with internal numbering
%% Create data structure
fprintf('\nCreating Y matrix of input full model');
[CIndx,ERP,DataB]=BuildYMat(NFROM,NTO,BraNum,LineB,BCIRC,BusNum,NUMB,SelfB);
%% Do Reduction
fprintf('\nDo first round reduction eliminating all external buses');
[mpcreduced,BCIRCr,ExBusr] = DoReduction(DataB,ERP,CIndx,ExBus,NUMB,dim,BCIRC,newbusnum,oldbusnum,mpc); % ExBusr with original numbering
%% Generate the second reduction with all retained buses and all generator
%% buses mpcreduced_gen
% Create the ExBus_Gen to create the reduced model with all gens
tf = ismember(ExBus,mpc.gen(:,1));
ExBusGen = ExBus;
ExBusGen(tf==1)=[]; % delete all external buses with generators
tf=ismember(mpc.gen(:,1),ExBus);
fprintf('\n%d external generators are to be placed',length(tf(tf==1)));
if ~isempty(ExBusGen)
fprintf('\nDo second round reduction eliminating all external non-generator buses');
[mpcreduced_gen,BCIRC_gen,ExBusGen] = DoReduction(DataB,ERP,CIndx,ExBusGen,NUMB,dim,BCIRC,newbusnum,oldbusnum,mpc);
else
    mpcreduced_gen = mpc;
    mpcreduced_gen=MapBus(mpcreduced_gen,newbusnum,oldbusnum);
    BCIRC_gen = BCIRC;
end
%% Move Generators
fprintf('\nPlacing External generators');
[NewGenBus,Link]=MoveExGen(mpcreduced_gen,ExBusOrig,ExBusGen,BCIRC_gen,0);
mpcreduced.gen(:,1)=NewGenBus; % move all external generators
%% Do Inverse PowerFlow
fprintf('\nRedistribute loads');
mpc=MapBus(mpc,newbusnum,oldbusnum);
[mpcreduced,BCIRCr]=LoadRedistribution(mpc,mpcreduced,BCIRCr,Pf_flag);
else
    mpcreduced = mpc;
    warning('No external buses, reduced model is same as full model');
end
%% Delete large reactance equivalent branches
ind=find(abs(mpcreduced.branch(:,4))>=max(mpc.branch(:,4))*10);
mpcreduced.branch(ind,:)=[];
BCIRCr(ind)=[];
%% Print Results
fprintf('\n**********Reduction Summary****************');
fprintf('\n%d buses in reduced model',size(mpcreduced.bus,1));
fprintf('\n%d branches in reduced model, including %d equivalent lines',size(mpcreduced.branch,1),length(BCIRCr(BCIRCr==max(BCIRCr))));
fprintf('\n%d generators in reduced model',size(mpcreduced.gen,1));
if isfield(mpcreduced,'dcline')
fprintf('\n%d HVDC lines in reduced mode,',size(mpcreduced.dcline,1));
end
fprintf('\n**********Generator Placement Results**************');
for i=1:size(Link,1)
    if Link(i,2)-Link(i,1)~=0
        fprintf('\nExternal generator on bus %d is moved to %d',Link(i,1),Link(i,2));
    end
end
fprintf('\n');

end