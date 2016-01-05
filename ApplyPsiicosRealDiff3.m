%% Set params
FolderName = 'C:/brainstorm_db/PSIICOS/data/';
bUseHR = false;
ChUsed = 1:306; ChUsed(3:3:end) = [];
TimeRange = [0, 0.700];
Conditions = {'1','2','4'}; % '2','4'};
Ncond = length(Conditions);
Band = [18 21];
%Band = [8 12];
bLoadTrials = true;
bComputePLI = false;
Fsamp = 500;
[b,a] = butter(5,Band/(Fsamp/2));
Protocol = bst_get('ProtocolStudies','PSIICOS');
clear ConData;
fprintf('Loading real data from BST database.. \n');
%% Load data and compute cross-spectral matrix 
ConditionsFound = 0;
clear ConData;
sc = 1;
for c = 1:length(Conditions)
    for s = 1:length(Protocol.Study)
        if(strcmp(Protocol.Study(s).Name,Conditions{c}))
            fprintf('Found study condition %s \n ', Conditions{c}); 
            for hm = 1:length(Protocol.Study(s).HeadModel)
                if(strcmp(Protocol.Study(s).HeadModel(hm).Comment,'Overlapping spheres_HR'))
                    ConData{sc}.HM_HR = load([FolderName Protocol.Study(s).HeadModel(hm).FileName]);
                else
                    ConData{sc}.HM_LR = load([FolderName Protocol.Study(s).HeadModel(hm).FileName]);
                end
            end;
            sc = sc+1;
        end;
    end;
end;
%% Reduce tangent dimension and transform into virtual sensors 
% the forward model is the same for both conditions
% so pick the first oneCOnData
GainSVDTh = 0.01;
Nch    = length(ChUsed);
for c = 1:length(ConData)
    ConData{c}.NsitesLR = size(ConData{c}.HM_LR.GridLoc,1);
    ConData{c}.G2dLR = zeros(Nch,ConData{c}.NsitesLR*2);
    % reduce tangent space
    range = 1:2;
    for i=1:ConData{c}.NsitesLR
        g = [ConData{c}.HM_LR.Gain(ChUsed,1+3*(i-1)) ...
             ConData{c}.HM_LR.Gain(ChUsed,2+3*(i-1)) ...
             ConData{c}.HM_LR.Gain(ChUsed,3+3*(i-1))];
        [u sv v] = svd(g);
        gt = g*v(:,1:2);
        ConData{c}.G2dLR(:,range) = gt*diag(1./sqrt(sum(gt.^2,1)));
        range = range + 2;
    end;
    
    %reduce sensor space
    [ug sg vg] = spm_svd(ConData{c}.G2dLR*ConData{c}.G2dLR',GainSVDTh);
    ConData{c}.UP = ug';
    ConData{c}.G2dLRU = ConData{c}.UP*ConData{c}.G2dLR;
    
    if(bUseHR)
        ConData{c}.NsitesHR = size(ConData{c}.HM_HR.GridLoc,1);
        ConData{c}.G2dHR = zeros(Nch,ConData{c}.NsitesHR*2);
        % reduce tangent space
        range = 1:2;
        for i=1:ConData{c}.NsitesHR
            g = [ConData{c}.HM_HR.Gain(ChUsed,1+3*(i-1)) ...
                 ConData{c}.HM_HR.Gain(ChUsed,2+3*(i-1)) ...
                 ConData{c}.HM_HR.Gain(ChUsed,3+3*(i-1))];
            [u sv v] = svd(g);
            gt = g*v(:,1:2);
            ConData{c}.G2dHR(:,range) = gt*diag(1./sqrt(sum(gt.^2,1)));
            range = range + 2;
        end;
    end;
    c;
end;

sc = 1;
ConditionsFound = 0;
for c = 1:length(Conditions)
    for s = 1:length(Protocol.Study)
        if(strcmp(Protocol.Study(s).Name,Conditions{c}))
            fprintf('Found study condition %s \n : ', Conditions{c}); 
            ConData{sc}.NumTrials = length(Protocol.Study(s).Data);
            if(bLoadTrials)
                fprintf('Loading Trials (Max %d) : ', ConData{sc}.NumTrials); 
    %            UP = ConData{fix((sc-1)/Ncond)*Ncond+1}.UP;
                UP = ConData{sc}.UP;
                for t = 1:ConData{sc}.NumTrials
                    aux = load([FolderName Protocol.Study(s).Data(t).FileName]);
                    if(t==1)
                         ConData{sc}.Trials = zeros(size(UP,1),length(aux.Time));
                         ConData{sc}.Time = aux.Time;
                         ConData{sc}.Fsamp = 1./(aux.Time(2)-aux.Time(1));
                    end;
                    %tmp = filtfilt(b,a,(UP*aux.F(ChUsed,:))')';
                    %ConData{sc}.Trials(:,:,t) = tmp(:,ind0:ind1);
                    ConData{sc}.Trials(:,:,t) = UP*aux.F(ChUsed,:);
                    %ConData{sc}.Trials0(:,:,t) = aux.F(ChUsed,:);
                    if t>1
                        for tt=0:log10(t-1)
                            fprintf('\b'); % delete previous counter display
                        end
                    end
                    fprintf('%d', t);
                end; % trials t
                fprintf(' -> Done\n');
            end;
            sc = sc+1;
         end;
    end;
end;
disp('Saving ... \n');
save('c:\mywriteups\irAPMusicPaper\10SubjData.mat','-v7.3');
return
load('c:\mywriteups\irAPMusicPaper\10SubjData.mat');
% do band-pass filtering and create ConDataBand
for sc = 1:length(ConData)
    for t = 1:size(ConData{sc}.Trials,3)
        [~, ind0] =min(abs(aux.Time-TimeRange(1)));
        [~, ind1] =min(abs(aux.Time-TimeRange(2)));
        T = ind1-ind0+1; 
        tmp = filtfilt(b,a,(ConData{sc}.Trials(:,:,t))')';
        ConDataBand{sc}.Trials(:,:,t) = tmp(:,ind0:ind1);
    end;
    sc
end;

for sc = 1:length(ConDataBand)
    fprintf('%d Computing cross-spectral matrix ....\n' , sc); 
    ConDataBand{sc}.CrossSpecTime = CrossSpectralTimeseries( ConDataBand{sc}.Trials);
    ConDataBand{sc}.CrossSpecTimeInd = CrossSpectralTimeseries( ConDataBand{sc}.Trials,true);
    % compute their projected versions
    [ConDataBand{sc}.CrossSpecTimeP, ConDataBand{sc}.Upwr] = ProjectAwayFromPowerFixedOr(ConDataBand{sc}.CrossSpecTime, ConData{sc}.G2dLRU,350);
    ConDataBand{sc}.CrossSpecTimeIndP = ConDataBand{sc}.CrossSpecTimeInd - ConDataBand{sc}.Upwr*ConDataBand{sc}.Upwr'*ConDataBand{sc}.CrossSpecTimeInd;
    %UP
    if(bComputePLI)
        Trials = zeros(size(ConData{sc}.UP,2),size(ConData{sc}.Trials,2),size(ConData{sc}.Trials,2));
        for tr = 1:size(ConData{sc}.Trials,3)
            Trials(:,:,tr) = ConData{sc}.UP'*ConData{sc}.Trials(:,:,tr);
        end;
        ConDataBand{sc}.wPLI =  wPLIMatrix(Trials(:,1:256,:),Band,Fsamp,true);
    end;
end;

Acc = zeros(1,351);
for s=1:10
    A2 = ConDataBand{10+s}.CrossSpecTimeIndP;
    A1 = ConDataBand{s}.CrossSpecTimeIndP;
    for t = 1:351
        N = size(ConData{10+s}.UP,1);
        Ad21 = ConData{10+s}.UP'*reshape(A2(:,t)-A1(t),N,N)*ConData{10+s}.UP;
        Acc(t) = Acc(t)+sum(Ad21(:));
    end;
end;


load('c:\MyWriteups\iRAPMusicPaper\Simulations\MEGSensors.mat');
for i = 1:length(ChUsed)
    ChLoc(:,i) = MEGSensors.Channel(ChUsed(i)).Loc(:,1);
end;

range = 75:150;
figure
pcntg = 2*1e-3;
for s=1:10
     C1 = ConDataBand{10+s}.CrossSpecTimeIndP(:,range)-ConDataBand{s}.CrossSpecTimeIndP(:,range);
     C2 = ConDataBand{20+s}.CrossSpecTimeIndP(:,range)-ConDataBand{s}.CrossSpecTimeIndP(:,range);
     [u ss2 v] = svd([real(C2) imag(C2)]);
     C1but2 = C1-u(:,1:6)*u(:,1:6)'*C1;
     [u ss1 v] = svd([real(C1) imag(C1)]);
     C2but1 = C2-u(:,1:6)*u(:,1:6)'*C2;
     C = sum(C1but2(:,1:50),2);

%     C2 = ConDataBand{10+s}.CrossSpecTimeIndP(:,75:200);
%     C1 = ConDataBand{s}.CrossSpecTimeIndP(:,75:200);
%     
%     [u ss v] = svd([real(C1) imag(C1)]);
%     C2but1 = C2-u(:,1:15)*u(:,1:15)'*C2;
%     C = sum(C2but1(:,1:50),2);
%    
    Csq = reshape(C,size(ConData{10+s}.UP,1),size(ConData{10+s}.UP,1));
    
    D21{s} = ConData{10+s}.UP'*Csq*ConData{10+s}.UP;
    M = abs(real(D21{s}));
    %M = (ConDataBand{20+s}.wPLI-ConDataBand{s}.wPLI)-(ConDataBand{10+s}.wPLI-ConDataBand{s}.wPLI);
    [aux, key_srt] = sort(M(:));
    ind_max = key_srt(fix((1-pcntg)*length(key_srt)):end);
    th = aux(fix((1-pcntg)*length(key_srt)));

    h = subplot(2,5,s)
      plot3(ChLoc(1,:),ChLoc(2,:),ChLoc(3,:),'.');

      hold on
      Pairs{s} = [];
       for i=1:length(ind_max)
          [ii jj]  = ind2sub(size(D21{s}),ind_max(i));
          Pairs{s} = [Pairs{s};[ii jj]];
          plot3([ChLoc(1,ii) ChLoc(1,jj)],[ChLoc(2,ii) ChLoc(2,jj)],[ChLoc(3,ii) ChLoc(3,jj)],'Color','r');
        end;
        set(h,'View',[0 90])
        axis tight
        axis off
end
CSa = zeros(10,10);
for s1 = 1:10
    for s2 = 1:10
        if(s1~=s2)
            CSa(s1,s2) = ConnectivitySimilarity(Pairs{s1},Pairs{s2},ChLoc);
        end
    end;
end;

return
sc = 1;
Trials1 = zeros(size(ConData{sc}.UP,2),size(ConData{sc}.Trials,2),size(ConData{sc}.Trials,2));
for tr = 1:size(ConData{sc}.Trials,3)
    Trials(:,:,tr) = ConData{sc}.UP'*ConDataBand{sc}.Trials(:,:,tr);
end;
Ep1 = squeeze(Trials(Pairs{1}(1,1),:,:))';
Ep2 = squeeze(Trials(Pairs{1}(1,2),:,:))';
Ep1Ind = Ep1-repmat(mean(Ep1,1),size(Ep1,1),1);
Ep2Ind = Ep2-repmat(mean(Ep1,1),size(Ep1,1),1);


for sc = 1:length(ConData)
    SubjInd = fix((sc-1)/Ncond)*Ncond+1;
    ConData{sc}.CrossSpecTimeNoVC = ProjectAwayFromPower(ConData{sc}.CrossSpecTime,ConData{SubjInd}.G2dLRU);
end;


CT3  = ProjectAwayFromPower(ConData{3}.CrossSpecTime,G2dLRU);
[u2 s2 v2 ] = svd(CT2,'econ');
CT3no2 = CT3-u2(:,1:20)*(u2(:,1:20)'*CT3);

[ Cs, CT, IND, Upwr] = RAPPSIICOSTime2Cond(ConData{3}.CrossSpecTime, ConData{2}.CrossSpecTime,CT2,20,G2dLRU ,1,350, 5);





%ConData{2}.CrossSpecTime = CrossSpectralTimeseries( ConData{2}.Trials);
%ConData{3}.CrossSpecTime = CrossSpectralTimeseries( ConData{3}.Trials);
%[Qpsiicos, IND, CpProjs ] = RAPPSIICOS(ConData{2}.CrossSpec-ConData{1}.CrossSpec, G2dLRU,G2dHRU,4);
%[Qpsiicos, IND, CpProjs ] = RAPPSIICOS(ConData{3}.CrossSpec-ConData{1}.CrossSpec, G2dLRU,G2dHRU,3);
%[Q3vs1, IND, CpProjs3vs1, Upwr ] = PSIICOS(ConData{3}.CrossSpec-ConData{1}.CrossSpec, G2dLRU);
%[Q2vs1, IND, CpProjs2vs1, Upwr ] = PSIICOS(ConData{2}.CrossSpec-ConData{1}.CrossSpec, G2dLRU);
%[Q3, IND, CpProjs3, Upwr ] = PSIICOS(ConData{3}.CrossSpec, G2dLRU);
%[Q2, IND, CpProjs2, Upwr ] = PSIICOS(ConData{2}.CrossSpec, G2dLRU);
return

[Q3vs1T, IND, CpProjs3vs1, Upwr ] = RAPPSIICOSTime(ConData{3}.CrossSpecTime-ConData{1}.CrossSpecTime, G2dLRU,4);
%[Cs3, Ps, INDdics] = iDICS(ConData{3}.CrossSpec, G2dLRU);
%[Cs1, Ps, INDdics] = iDICS(ConData{1}.CrossSpec, G2dLRU);

return
Cons = [1,3];
Ntr = size(ConData{3}.Trials,3);
for mc = 1:100
    trials = fix(0.99*rand(1,Ntr)*Ntr+1);
    CrossSpec = CrossSpectralMatrix(ConData{3}.Trials(:,:,trials),Band,500);
    [Qpsiicosmc, IND, CpProjs ] = RAPPSIICOS(CrossSpec-ConData{1}.CrossSpec, G2dLRU,G2dHRU,4);
    fname = sprintf('qpsiicos_mc_trial_%d.mat',mc);
    save(fname,'Qpsiicosmc');
%    QQmc{mc} = Qpsiicosmc;
end;
    
return
Ctx = load('D:\Brainstorm_db\PSIICOS\anat\0003_pran\tess_cortex_concat_2000V.mat');
%4175428 29
figure;
hctx  = trisurf(Ctx.Faces,Ctx.Vertices(:,1),Ctx.Vertices(:,2),Ctx.Vertices(:,3),'FaceColor',[0.1,0.51,1], 'EdgeColor','none','FaceAlpha', 0.3);
hold on;
camlight left; lighting phong
camlight right; 
hold on;

cols = ['r','g','m','y','k','c']
D =sum(Cs{1},2);
R = ConData{1}.HM_LR.GridLoc;
for k=1:size(D,2)
    Dmx = max(D(:,k));
    ind = find(D(:,k)>0.93*Dmx);
    for i=1:length(ind)
        h = line([R(IND(ind(i),1),1) R(IND(ind(i),2),1)],[R(IND(ind(i),1),2) R(IND(ind(i),2),2)],[R(IND(ind(i),1),3) R(IND(ind(i),2),3)] );
        plot3(R(IND(ind(i),1),1),R(IND(ind(i),1),2),R(IND(ind(i),1),3),[cols(k) '.']);
        plot3(R(IND(ind(i),2),1),R(IND(ind(i),2),2),R(IND(ind(i),2),3),[cols(k) '.']);
        set(h,'Color',cols(k),'LineWidth',2);
    end;
end;

clear CP;
CP = Cp{1}; 
[Qs key] = sort(QpsiicosP{1});
INDs = IND{1}(key,:);
tmp0 = CP;
a0 = norm(tmp0(:));
aa = zeros(1,100);
VV = [];
for r=1:100
    ii = INDs(end-k+1,1);
    jj = INDs(end-k+1,2);
    range_i = ii*2-1:ii*2;
    range_j = jj*2-1:jj*2;
    gi = G2dU(:,range_i);
    gj = G2dU(:,range_j);
    V = zeros(73^2, 4);
    Vre = zeros(73^2, 4);
    Vim = zeros(73^2, 4);
    k = 1;
    for i=1:2
        for j=1:2
            gg =bsxfun(@times,gi(:,i),gj(:,j)'); 
            v = gg+gg';
            Vre(:,k) = v(:);
            v = gg-gg';
            Vim(:,k) = v(:);
            k = k+1;
        end;
    end;
    VV= [VV V];
    [u s v] = svd(VV,'econ');
    c = u'*CP(:);
    CPp = reshape(CP(:)-u*c,73,73);
%    aare(k) = norm(real(tmp1(:)))/norm(real(tmp0(:)));
%    aaim(k) = norm(imag(tmp1(:)))/norm(imag(tmp0(:)));
    aa(r) = norm((CPp(:)))/norm((CP(:)));
end;

for mc=1:40
    fname = sprintf('qpsiicos_mc_trial_%d.mat',mc);
    h = load(fname);

    D = h.Qpsiicosmc;
    R = ConData{1}.HM_LR.GridLoc;
    for k=1:size(D,2)
        [Dmx ind] = max(D(:,k));
        for i=1:length(ind)
         h = line([R(IND(ind(i),1),1) R(IND(ind(i),2),1)],[R(IND(ind(i),1),2) R(IND(ind(i),2),2)],[R(IND(ind(i),1),3) R(IND(ind(i),2),3)] );
        plot3(R(IND(ind(i),1),1),R(IND(ind(i),1),2),R(IND(ind(i),1),3),[cols(k) '.']);
        plot3(R(IND(ind(i),2),1),R(IND(ind(i),2),2),R(IND(ind(i),2),3),[cols(k) '.']);
        set(h,'Color',cols(k));
        end;
    end;
    mc
end



