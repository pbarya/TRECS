!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! This program is part of the T-RECS code
! Author: A. Bonaldi
! see Bonaldi et al. (2018) MNRAS for more details
! generate samples of HI galaxies from models
! save outputs to files per redshift bin 
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

program sampler

  use healpix_types
  USE fitstools
  USE utilities
  USE pix_tools
  USE random_tools
  use random,only:random_poisson,random_normal
  use sampler_io
  use trecs_mods
  use interpolations
  use cosmology
  USE paramfile_io, ONLY : paramfile_handle, parse_init, parse_int, &
       parse_string, parse_double, parse_lgt, concatnl, parse_real
  USE extension, ONLY : getEnvironment, getArgument, nArguments
  implicit none

  !parameters
  real(sp),parameter::zmax=8.
  CHARACTER(LEN=*), PARAMETER :: code ="T-RECS"
  real(dp),parameter:: fullsky_area=41253._dp
  REAL, PARAMETER :: pc=3.0856776E18 !Pc in cm
  real, parameter::sterad_deg=3283. 
  REAL, PARAMETER :: Mpc=10.**6*pc
!!$  integer,parameter::Nmbins=10
!!$  integer,parameter::mass_scatter=1
!!$  real(sp),parameter::flagvalue=-100.

  !character variables
  character(LEN=filenamelen)::paramfile,description,dummy,outdir,MHI_filename,MHI2Mh_filename
  real(dp)::nu,deltanu,sfr,mn,mx,volume,integ,volumetot,fom,fom_old,z_i
  character(LEN=filenamelen)::chline,filestat,cat_filename
  character(LEN=16),allocatable::tagnames(:),tunit(:),tform(:)
  !character(LEN=10)::names(3)
  CHARACTER(LEN=5) :: output,output2,tag
  CHARACTER(LEN=10) ::output3
  CHARACTER(LEN=80), DIMENSION(1:120) :: header
  CHARACTER(LEN=7)::line,col_str,zstr_long
  CHARACTER(LEN=4),allocatable::redshift_names(:)
  CHARACTER(LEN=4) ::zstr

  !single precision variables
  real(sp)::z_min,z_max,mu,clock_time,coo_max,coo_min
  real(sp)::masslim,fluxlim,dm_model,dim,sin_i,cos_i
  real(sp)::q,q2,d_a,flux,flux_conv,rn
  real(sp),allocatable::samplex(:),samplex_slice(:),samplex_copy(:),redshifts(:)
  real(sp),allocatable::zall_slice(:),zall_copy(:)
  real(sp),allocatable::catout(:,:),z_gals(:),sizes(:),fluxes(:),fluxes_slice(:),fluxes_copy(:)
  real(sp),allocatable::darkmass(:),latitudes(:),longitudes(:),inclinations(:)
  real(sp),allocatable::bmaj(:),bmin(:),pa(:),qrat(:)
  real(sp),allocatable::MHItab(:),Mhalotab(:)

!!$  !double precision variables
  real(dp)::sim_area,skyfrac,d_l
  real(dp)::sim_side
  real(dp),allocatable::data(:,:),x(:),px(:)
  real(dp)::Ngen_db,norm
  real(dp)::dx,xmin,xmax,zlow,zhigh,z
  integer*8::Nsample,test
  integer::buffer_size,buffer_free,jbuf,buffer_free_old,buffer_size_old,l_outdir
  integer::Nsample_old,Nfunction,Nsample_surv,nreds_out,nreds,Ncat_HI,nrows,Ncolumns,nrows_lf,nskip,zi
  integer(4) :: ic4, crate4, cmax4!,ni,sum_plus,p14(1),i14,ilim,i48,p(1),p_i,try
  integer::seed(34),iseed,iostat,seed_fix
  INTEGER, DIMENSION(8,2) :: values_time
  integer::N,Nran,i,j!,reason,iunit
  integer,allocatable::poisson_numbers(:)
  logical::first=.true.

!!$  !types variables
  TYPE(paramfile_handle) :: handle

  save iseed

  call date_and_time(values = values_time(:,1))
  call system_clock(count=ic4, count_rate=crate4, count_max=cmax4)
  iseed=ic4
  test=rand(time())


  ! check calling sequence
  if (nArguments() == 0) then
     paramfile=''
  else if (nArguments() == 1) then

     call getArgument(1,paramfile)
     filestat='old'
  else
     print '("Usage: sampler: [parameter file name]")'
     stop 1
  endif


  ! --- declaration of intent                                                                                       
  PRINT*," "
  PRINT*,"               "//code
  PRINT*," "

  !*************************************                                                                                       
  !read input parameters from file or interactively                                                                                        
  !************************************                                                                                        

  handle = parse_init(paramfile)

  description = concatnl( &
       & " Enter the simulation size: ")
  sim_side = parse_double(handle, 'sim_side', default=5.d0, vmin=0.d0, descr=description)

  description = concatnl( &
       & " Enter the flux limit [Jy Hz]: ")
  fluxlim = parse_double(handle, 'fluxlim', default=1.d0, descr=description)

  description = concatnl( &
       & " Enter the minimum redhift to consider: ")
  z_min = parse_real(handle, 'z_min', default=0., vmin=0., descr=description)

  description = concatnl( &
       & " Enter the maximum redshift to consider: ")
  z_max = parse_real(handle, 'z_max', default=0.5, vmin=0., descr=description)

  description = concatnl( &
       & " Enter the name of the the output file directory:")
  outdir=  parse_string(handle, 'outdir', default='.', descr=description)


  description = concatnl( &
       & " Do you want to skip the AGN simulation (0=no, 1=yes)")
  seed_fix = parse_int(handle, 'seed', default=-1, descr=description)
  ! end reading input parameters


  !'Seeding random number generators'
  !getting seed for random number generation from the clock

  if (seed_fix ==-1) then
     call system_clock(count=ic4, count_rate=crate4, count_max=cmax4)
     do i=1,34
        seed(i)=ic4*i/12.+iseed  ! combining two clock readings to fill 12 seeds
     enddo
  else
     do i=1,34
        seed(i)=1284350*i+seed_fix  ! combining two clock readings to fill 12 seeds
     enddo
     iseed=seed_fix
  endif

  call random_seed(PUT=seed)  ! feeding to Poisson and Gaussian generator 
  rn=rand(iseed+807820) ! initialise random uniform generator


  !string formatting: eliminate spaces between path anf file name
  outdir=ADJUSTL(outdir)
  l_outdir=LEN_TRIM(outdir)


  !simulation area 
  sim_area=sim_side*sim_side
  skyfrac=sim_area/fullsky_area

  print*,'simulation area [square degrees]=',sim_area


  ! debug message on the size of the field
  coo_max=sim_side/2.
  coo_min=-1.*coo_max
  print*,'coordinates',coo_max,coo_min

  !AGN simulation follows. If no AGN simulation is needed this is skipped



  !*************************
  !HI simulation starts
  !*************************


  !structure of the catalogue
  Ncat_hi=15 ! hi mass, dark mass, latitude, longitude

  !creating tag names for the catalogue
  allocate(tagnames(Ncat_hi),tunit(Ncat_hi),tform(Ncat_hi))
  j=1
  tagnames(j)='MHI'
  tunit(j)='log(Msun)'
  j=j+1
  tagnames(j)='HI flux'
  tunit(j)='mJy Hz'
  j=j+1
  tagnames(j)='Mh'
  tunit(j)='log(Msun)'
  j=j+1
  tagnames(j)='x_coord'
  tunit(j)='degs'
  j=j+1
  tagnames(j)='y_coord'
  tunit(j)='degs'
  j=j+1
  tagnames(j)='latitude'
  tunit(j)='degs'
  j=j+1
  tagnames(j)='longitude'
  tunit(j)='degs'
  j=j+1
  tagnames(j)='redshift'
  tunit(j)='none'
  j=j+1
  tagnames(j)='HI size'
  tunit(j)='arcsec'
  j=j+1
  tagnames(j)='inclination'
  tunit(j)='degs'
  j=j+1
  tagnames(j)='axis ratio'
  tunit(j)='none'
  j=j+1
  tagnames(j)='bmaj'
  tunit(j)='arcsec'
  j=j+1
  tagnames(j)='bmin'
  tunit(j)='arcsec'
  j=j+1
  tagnames(j)='PA'
  tunit(j)='degs'
  j=j+1
  tagnames(j)='OptClass'
  tunit(j)='none'



  tform(:)='1E'

  nreds=12 !HI galaxies up to z=0.5 only
  nreds_out=nreds

  allocate(redshifts(nreds),redshift_names(nreds))

  redshifts=(/0.01,0.02,0.05,0.10,0.15,0.20,0.25,0.30,0.35,0.40,0.45,0.50,0.55,&
       0.60,0.65,0.70,0.75,0.80,0.85,0.90,0.95,1.00,1.20,1.40,1.60,1.80,2.00,2.20,2.40,&
       2.60,2.80,3.00,3.20,3.40,3.60,3.80,4.00,4.20,4.40,4.60,4.80,5.00,5.20,5.40,5.60,5.80,&
       6.00,6.20,6.40,6.60,6.80,7.00,7.20,7.40,7.60,7.80,8.00,8.20,8.40,8.60,8.80,9.00,9.20,9.40,9.60,9.80,10.00/)

  redshift_names=(/'0.01','0.02','0.05','0.10','0.15','0.20','0.25','0.30','0.35','0.40','0.45','0.50',&
       '0.55','0.60','0.65','0.70','0.75','0.80','0.85','0.90','0.95','1.00','1.20','1.40','1.60','1.80','2.00'&
       ,'2.20','2.40','2.60','2.80','3.00','3.20','3.40','3.60','3.80','4.00','4.20','4.40','4.60','4.80','5.00'&
       ,'5.20','5.40','5.60','5.80','6.00','6.20','6.40','6.60','6.80','7.00','7.20','7.40','7.60','7.80','8.00',&
       '8.20','8.40','8.60','8.80','9.00','9.20','9.40','9.60','9.80','10.0'/)


  !count how many redshift bins within the range
  if (zmax < maxval(redshifts)) then
     nreds_out=0
     i=1
     do  while (redshifts(i)<=zmax)
        nreds_out=nreds_out+1
        i=i+1
     enddo
     nreds_out=nreds_out+1
  endif


  ! main redshift loop
  do zi=1,nreds_out-1
     z=redshifts(zi)


     if ((z_min <= z) .and. (z_max >= z)) then    ! redshift slice with center z is processed

        d_l=lumr(dble(z))!angular diameter distance of the centre of the slice (Mpc)
        flux_conv=d_l**(-2.)/49.8 !Duffy et al. (2012)
        masslim=log10(fluxlim/flux_conv) ! mass limit corresponding to the flux limit specified
        print*,'Mass limit =',masslim



        !getting the size of the redshift slice
        select case (zi)
        case (1)
           zlow=0.
           zhigh=(redshifts(zi+1)+z)/2.
        case default
           zlow=(redshifts(zi-1)+z)/2.
           zhigh=(redshifts(zi+1)+z)/2.
        end select

        print*,'************************'
        print*,'HI: Processing redshift',z,' Range',zlow,zhigh
        print*,'************************'

        zstr=redshift_names(zi) 

        volumetot=4.*pi/3.*(r(zhigh)**3-r(zlow)**3)
        volume=volumetot*skyfrac  !volume corresponding to FoV
        print*,'volume=',volume

        !relation between L14 and mass of dark halo, from abundance matching
        ! reading from a file

        !Reading HI mass functions
        MHI_filename='../../TRECS_Inputs/MHIF/MHIF_z'//zstr//'.dat'  

        Ncolumns=2
        nrows=rows_number(MHI_filename,1,nskip)
        Nrows_lf=nrows

        allocate(data(nrows,ncolumns),x(nrows),px(nrows))
        call read_columns(MHI_filename,2,nrows,Ncolumns,nskip,data)
        !data(:,1) =log(MHI)
        !data(:,2) =log(phitot)

        x=data(:,1) !log(MHI)
        px=10.**data(:,2)


        Nsample_old=0
        buffer_size=1000
        buffer_free=buffer_size
        jbuf=0 ! index to fill buffer 


        integ=trapint(x,px) ! integral with trapezium rule for the PDF, to give the number of galaxies 

        print*,'number of galaxies for Mpc**3',integ

        norm=volume*integ/sum(px) ! normalisation for histogram 
        Ngen_db=volume*integ
        N=Nrows_lf 

        allocate(poisson_numbers(N),stat=iostat)

        if (iostat /= 0.) then 
           print*,'deallocation error poisson numbers!'
        endif

        ! Poisson sampling to get number of object per SFR bin from the PDF
        do i=1,N
           mu=real(Px(i)*norm)
           Nran=random_Poisson(mu, first)! integer from poisson distribution with mean mu
           poisson_numbers(i)=Nran
        enddo
        Nsample=sum(poisson_numbers) ! this is the number of galaxies to be generated

        !Nothing to be done if there are no galaxies
        if (Nsample==0) then
           deallocate(poisson_numbers)
           goto 500
        endif

        if (Nsample < buffer_size) buffer_size=Nsample

        allocate(samplex(buffer_size),z_gals(buffer_size),fluxes(buffer_size)) 
        if (iostat/=0) then
           print*,'sampler: allocation error'
           stop
        endif

        samplex(:)=0.
        z_gals(:)=0.
        fluxes(:)=0.

        dx=abs(x(2)-x(1))

        ! generating HI mass values for the galaxies from the PDF

        Nsample_surv=0

        !print*,poisson_numbers,sum(poisson_numbers)



        do i=1,N
           Nran=poisson_numbers(i)
           xmax=x(i)+dx/2
           xmin=x(i)-dx/2

           if (xmin >= masslim) then  


              allocate(samplex_slice(Nran),zall_slice(Nran),fluxes_slice(Nran))

              do j=1,Nran
                 samplex_slice(j)=rand()*(xmax-xmin)+xmin
                 !                 samplex_slice(j)=random_normal()*(xmax-xmin)+xmin


                 zall_slice(j)=rand()*(zhigh-zlow)+zlow

                 d_l=lumr(dble(zall_slice(j))) ! luminosity distance MPc
                 flux_conv=d_l**(-2.)/49.8 !Jy/Hz
                 fluxes_slice(j)=flux_conv*(10.**samplex_slice(j)) ! flux in Jy/Hz
                 if (fluxes_slice(j)>= fluxlim) Nsample_surv= Nsample_surv+1  ! implement flux threshold
              enddo

              if (buffer_free < Nsample_surv) then 
                 ! expand buffer
                 Print*,'resize buffer'
                 buffer_size_old=buffer_size
                 buffer_free_old=buffer_free
                 buffer_size=buffer_size_old+(buffer_size_old+Nsample_surv)*10
                 buffer_free=buffer_free+(buffer_size_old+Nsample_surv)*10

                 allocate(samplex_copy(buffer_size_old),zall_copy(buffer_size_old),fluxes_copy(buffer_size_old))
                 !radioflux_copy=radioflux
                 samplex_copy=samplex
                 zall_copy=z_gals
                 fluxes_copy=fluxes

                 deallocate(samplex,z_gals,fluxes)
                 allocate(samplex(buffer_size),z_gals(buffer_size),fluxes(buffer_size))
                 samplex(1:buffer_size_old)=samplex_copy(:)
                 z_gals(1:buffer_size_old)=zall_copy(:)
                 fluxes(1:buffer_size_old)=fluxes_copy(:)

                 deallocate(samplex_copy,zall_copy,fluxes_copy)
              endif

              ! fill buffer

              ! flux limit
              do j=1,Nran
                 flux=fluxes_slice(j)
                 if (flux>= fluxlim) then
                    jbuf=jbuf+1
                    samplex(jbuf)=samplex_slice(j)
                    z_gals(jbuf)=zall_slice(j)
                    fluxes(jbuf)=fluxes_slice(j)
                 endif
              enddo
              buffer_free=buffer_size-jbuf

              deallocate(samplex_slice,zall_slice,fluxes_slice)
           endif
        enddo


        deallocate(poisson_numbers)



        Nsample=buffer_size-buffer_free
        print*,'Number of galaxies above flux limit',Nsample

        if (Nsample==0) then
           !skip resize and output catalogue if no object is found
           deallocate(samplex,z_gals,fluxes,x,px,data)
           goto 500 
        endif

        ! resize Radioflux to the final sample size
        if (buffer_free /=0) then
           print*,'resize final catalogue' 
           allocate(samplex_copy(buffer_size),zall_copy(buffer_size),fluxes_copy(buffer_size),stat=iostat)
           if (iostat /=0) then
              print*,'Allocation error'
              stop
           endif
           samplex_copy=samplex
           zall_copy=z_gals
           fluxes_copy=fluxes
           deallocate(samplex,z_gals,fluxes,stat=iostat)
           if (iostat /=0) then
              print*,'Deallocation error'
              stop
           endif

           Nsample=buffer_size-buffer_free
           allocate(samplex(nsample),z_gals(nsample),fluxes(nsample),stat=iostat)
           if (iostat /=0) then
              print*,'Allocation error'
              stop
           endif
           samplex(:)=samplex_copy(1:Nsample)
           z_gals(:)=zall_copy(1:Nsample)
           fluxes(:)=fluxes_copy(1:Nsample)
           deallocate(samplex_copy,zall_copy,fluxes_copy,stat=iostat)
           if (iostat /=0) then
              print*,'Deallocation error'
              stop
           endif
        endif


        print*,'MHIs generated'

        ! compute halo mass from sfr 
        allocate(Darkmass(Nsample),latitudes(Nsample),&
             &longitudes(Nsample),sizes(Nsample),&
             &inclinations(Nsample),qrat(Nsample),bmaj(Nsample),&
             &bmin(Nsample),pa(Nsample),stat=iostat)
        if (iostat/=0) then
           print*,'sampler: allocation error'
           stop
        endif

!!$
!!$           do i=1,Nsample
!!$              th=rand()*2.*pi*2. !2theta
!!$              ellipticity2(i)=ellipticity1(i)*sin(th)
!!$              ellipticity1(i)=ellipticity1(i)*cos(th)
!!$           enddo
!!$           ! end ellipticities

        deallocate(x,px,data)

        !relation between HI and mass of dark halo, from abundance matching
        ! reading from a file
        MHI2Mh_filename='../../TRECS_Inputs/AbundanceMatch/results_HI/HI2DM_z'//zstr//'.txt' 
        Ncolumns=2
        nrows=rows_number(MHI2Mh_filename,1,nskip)
        Nfunction=nrows

        allocate(data(nrows,ncolumns),MHItab(nrows),Mhalotab(nrows))

        call read_columns(MHI2Mh_filename,2,nrows,Ncolumns,nskip,data)
        MHItab=data(:,1)
        Mhalotab=data(:,2)
        deallocate(data)
        !        minmass_cone=9.2 ! this is the minimum halo mass in the lightcone




        do i=1,Nsample
           dm_model=interpol(samplex(i),MHItab,Mhalotab,Nfunction)
           Darkmass(i)=dm_model ! halo mass to associate with BGC instead of satellite         

           latitudes(i)=(rand()-0.5)*sim_side  ! random coordinates
           longitudes(i)=(rand()-0.5)*sim_side
           z_i=dble(z_gals(i))

           !dim=(0.506+random_normal()*0.003)*samplex(i)-3.293+random_normal()*0.009 !log phys size kpc , Wang et al. 2016 eq 2.

           !Naluminsa et al. (2021)
           !logM_HI=(1.95 pm 0.03)log D_HI +(6.5 pm 0.04)
           !log D_HI = (0.51 pm 0.01) log M_HI - (3.33 pm 0.03)

           dim=(0.51+random_normal()*0.01)*samplex(i)-3.33+random_normal()*0.03 !log phys size kpc , Naluminsa et al. (2021)
           
           Dim=10.**dim/1000./2. !size in Mpc, radius instead of diameter
           sizes(i)=theta(dim,z_i)! apparent size. 
           !old: the 0.2 factor converts to exponential scale radius, wang et al. 2016 section 3.1



           !TODO: change this 

           cos_i=rand()
           inclinations(i)=acos(cos_i)*180./pi
           !the HI size is smaller than the radio size computed from here, but this could be due to the DM mass  modelled here. check after xmatch. 

           ! all HI galaxies have spiral morphology. start from an intrinsic axis ratio of 0.2
           q=0.2+random_normal()*0.05 
           q2=q**2 ! square alpha
           q=sqrt(q2+(cos(inclinations(i)))**2.*(1.-q2)) ! observed axis ratio, linked to inclination

           qrat(i)=q
           bmaj(i)=sqrt(sizes(i)**2./q) ! apparent bmaj

           ! size is the circularised profile
           !pi r^2=!pi ab, where  a and b are major and minor semi-axis
           !then I use b=q*a  and solve for a

           bmin(i)=q*bmaj(i)     ! apparent bmin
           pa(i)=rand()*360. !random PA in degs
        enddo

        !preparing to output the data in catalogue format

        !start filling the output catalogue array

        allocate(catout(Ncat_hi,Nsample),stat=iostat)
        if (iostat/=0) then
           print*,'sampler: allocation error'
           stop
        endif

        catout(1,:)=samplex(1:Nsample)       ! HI mass
        catout(2,:)=fluxes*1000. ! HI flux mJy/Hz
        catout(3,:)=darkmass       
        catout(4,:)=latitudes     !cartesian coordinates - to be projected on the sphere by wrapper
        catout(5,:)=longitudes
        catout(6,:)=0. ! spherical coordinates - to be filled by wrapper
        catout(7,:)=0. 
        catout(8,:)=z_gals
        catout(9,:)=sizes  
        catout(10,:)=inclinations
        catout(11,:)=qrat
        catout(12,:)=bmaj
        catout(13,:)=bmin
        catout(14,:)=pa
        catout(15,:)=2. ! all HI galaxies have spiral morphology

        ! compute intrinsic luminosities and store them in the catalogue if requested


        deallocate(samplex,fluxes,darkmass,&
             &latitudes,longitudes,z_gals,sizes,MHItab,Mhalotab,&
             &inclinations,pa,qrat,bmin,bmaj,stat=iostat)
        if (iostat/=0) then
           print*,'sampler: deallocation error'

        endif
500     continue

        if (Nsample /=0) then 
           print*,'writing'
           ! wrinting catalogue to disk
           cat_filename=outdir(1:l_outdir)//'/catalogue_HI_z'//zstr//'.fits'

           call write_catalogue_new(cat_filename,catout,Ncat_hi,tagnames,tunit,tform)
           ! catalogue written
           print*,'done'
           deallocate(catout)
        endif
     endif

  enddo !loop on redshifts

  !free all memory
  deallocate(redshifts,redshift_names)
  deallocate(tagnames,tunit,tform)

  ! compute time for the run
  call date_and_time(values = values_time(:,2))

  values_time(:,1) = values_time(:,2) - values_time(:,1)
  clock_time =  (  (values_time(3,1)*24 &
       &           + values_time(5,1))*60. &
       &           + values_time(6,1))*60. &
       &           + values_time(7,1) &
       &           + values_time(8,1)/1000.
  PRINT*,"Total clock time [m]:",clock_time/60.
  PRINT*,"               "//code//" > Normal completion"
end program sampler
